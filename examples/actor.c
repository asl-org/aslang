/* asl_pure.c — a purely functional actor runtime in C.
 *
 * The whole runtime is one persistent value: AslWorld. Every API
 * function has the shape
 *
 *      AslWorld f(AslWorld w, ...);        // world in, world out
 *
 * Nothing is mutated in place at the API boundary: you pass a world BY
 * VALUE, you get a new world BY VALUE. (Functions mutate their private
 * local copy — invisible from outside, so referential transparency
 * holds; this is C's version of Haskell's ST trick.)
 *
 * Consequences, all free:
 *   - determinism:  same world + same calls  => bit-identical world
 *   - time travel:  keep old worlds, resume from any of them
 *   - replay:       an event log of calls IS a full system recording
 *   - testability:  a test is just  assert(equal(f(w), expected))
 *
 * All actor state is a small VALUE (AslState: four i32 words), all
 * messages are values, mailboxes are by-value rings, capacities are
 * compile-time constants. No pointers escape, no heap, no free.
 * The only function pointer is the actor's pure step function:
 *
 *      AslStepOut step(AslState s, AslMsg m, int has_msg);   // PURE
 *
 * This file is the executable SPECIFICATION of the runtime. The
 * imperative arena/scheduler library is the optimized implementation;
 * "imperative version refines this one" is the proof obligation.
 */

#include <stdint.h>
#include <string.h>

/* ---- capacities (the whole world is a fixed-size value) --------------- */
#define ASL_MAX_ACTORS 8
#define ASL_MBOX_CAP 6
#define ASL_QUANTUM 3 /* K pure steps per quantum */

/* ---- values ------------------------------------------------------------ */

typedef uint8_t asl_id; /* 0 = none */
#define ASL_NONE ((asl_id)0)

typedef struct
{
  int32_t w[4];
} AslState; /* actor state: a value  */

typedef enum
{
  ASL_M_USER = 0,
  ASL_M_STOP = 1,
  ASL_M_DOWN = 2
} AslMsgKind;

typedef struct
{
  uint8_t kind;  /* AslMsgKind                          */
  asl_id sender; /* DOWN: the terminated child          */
  int32_t tag;   /* USER: app tag; DOWN: exit code      */
  int32_t val;   /* USER payload (a value, no pointer)  */
} AslMsg;

typedef enum
{
  ASL_S_CONTINUE = 0,
  ASL_S_WAITING = 1,
  ASL_S_DONE = 2,
  ASL_S_FAIL = 3
} AslStepKind;

typedef struct
{
  uint8_t kind;  /* AslStepKind                         */
  AslState next; /* state' (CONTINUE / WAITING)         */
  int32_t code;  /* DONE result / FAIL reason           */
} AslStepOut;

/* THE contract: a pure function of values to values. has_msg = 0 means
 * "resuming a CONTINUE" (m is all-zero and must be ignored). */
typedef AslStepOut (*AslBehavior)(AslState s, AslMsg m, int has_msg);

typedef enum
{
  ASL_A_FREE = 0,
  ASL_A_READY,
  ASL_A_WAITING,
  ASL_A_TERM
} AslActorStatus;

#define ASL_EXIT_KILLED (-2)

typedef struct
{
  AslBehavior fn;
  AslState state;
  uint8_t status; /* AslActorStatus                      */
  int32_t exit_code;
  asl_id parent;
  AslMsg mbox[ASL_MBOX_CAP];
  uint8_t head, count;
} AslActor;

typedef struct
{
  AslActor actors[ASL_MAX_ACTORS];
  uint8_t rr; /* round-robin cursor                  */
} AslWorld;

/* ---- constructors ------------------------------------------------------ */

static AslWorld asl_world_empty(void)
{
  AslWorld w;
  memset(&w, 0, sizeof w); /* zeroed padding => memcmp-comparable */
  return w;
}

static AslState asl_state(int32_t a, int32_t b, int32_t c, int32_t d)
{
  AslState s = {{a, b, c, d}};
  return s;
}

/* ---- internal helpers (operate on the LOCAL copy) ---------------------- */

static int mbox_push_back(AslActor *a, AslMsg m)
{
  if (a->count == ASL_MBOX_CAP)
    return 0;
  a->mbox[(a->head + a->count) % ASL_MBOX_CAP] = m;
  a->count++;
  return 1;
}

/* system messages (STOP/DOWN) jump the queue: push FRONT */
static int mbox_push_front(AslActor *a, AslMsg m)
{
  if (a->count == ASL_MBOX_CAP)
    return 0;
  a->head = (uint8_t)((a->head + ASL_MBOX_CAP - 1) % ASL_MBOX_CAP);
  a->mbox[a->head] = m;
  a->count++;
  return 1;
}

static AslMsg mbox_pop(AslActor *a)
{
  AslMsg m = a->mbox[a->head];
  a->head = (uint8_t)((a->head + 1) % ASL_MBOX_CAP);
  a->count--;
  return m;
}

static void wake(AslActor *a)
{
  if (a->status == ASL_A_WAITING)
    a->status = ASL_A_READY;
}

static void terminate(AslWorld *w, asl_id id, int32_t code)
{
  AslActor *a = &w->actors[id - 1];
  a->status = ASL_A_TERM;
  a->exit_code = code;
  if (a->parent != ASL_NONE)
  {
    AslActor *p = &w->actors[a->parent - 1];
    if (p->status != ASL_A_FREE && p->status != ASL_A_TERM)
    {
      AslMsg down = {ASL_M_DOWN, id, code, 0};
      mbox_push_front(p, down);
      wake(p);
    }
  }
}

/* ---- the pure API ------------------------------------------------------ */

typedef struct
{
  AslWorld world;
  asl_id id;
} AslSpawned;
typedef struct
{
  AslWorld world;
  int ok;
} AslSent;

static AslSpawned asl_spawn(AslWorld w, asl_id parent,
                            AslBehavior fn, AslState init)
{
  AslSpawned out;
  for (uint8_t i = 0; i < ASL_MAX_ACTORS; i++)
  {
    AslActor *a = &w.actors[i];
    if (a->status != ASL_A_FREE)
      continue;
    memset(a, 0, sizeof *a);
    a->fn = fn;
    a->state = init;
    a->parent = parent;
    a->status = ASL_A_READY; /* first step: no msg */
    out.world = w;
    out.id = (asl_id)(i + 1);
    return out;
  }
  out.world = w;
  out.id = ASL_NONE; /* full: world unchanged */
  return out;
}

static AslSent asl_send(AslWorld w, asl_id from, asl_id to,
                        int32_t tag, int32_t val)
{
  AslSent out;
  if (to == ASL_NONE || to > ASL_MAX_ACTORS)
  {
    out.world = w;
    out.ok = 0;
    return out;
  }
  AslActor *a = &w.actors[to - 1];
  if (a->status == ASL_A_FREE || a->status == ASL_A_TERM)
  {
    out.world = w;
    out.ok = 0;
    return out;
  }
  AslMsg m = {ASL_M_USER, from, tag, val};
  int ok = mbox_push_back(a, m); /* backpressure: reject  */
  if (ok)
    wake(a);
  out.world = w;
  out.ok = ok;
  return out;
}

static AslWorld asl_stop(AslWorld w, asl_id id) /* graceful */
{
  if (id == ASL_NONE || id > ASL_MAX_ACTORS)
    return w;
  AslActor *a = &w.actors[id - 1];
  if (a->status == ASL_A_FREE || a->status == ASL_A_TERM)
    return w;
  AslMsg m = {ASL_M_STOP, ASL_NONE, 0, 0};
  if (mbox_push_front(a, m))
    wake(a);
  return w;
}

static AslWorld asl_kill(AslWorld w, asl_id id) /* forceful */
{
  if (id == ASL_NONE || id > ASL_MAX_ACTORS)
    return w;
  AslActor *a = &w.actors[id - 1];
  if (a->status == ASL_A_FREE || a->status == ASL_A_TERM)
    return w;
  terminate(&w, id, ASL_EXIT_KILLED); /* between steps: safe   */
  return w;
}

/* One quantum: pick next READY actor round-robin, run <= K pure steps. */
static AslWorld asl_run_quantum(AslWorld w)
{
  uint8_t slot = 0, found = 0;
  for (uint8_t k = 0; k < ASL_MAX_ACTORS; k++)
  {
    uint8_t i = (uint8_t)((w.rr + k) % ASL_MAX_ACTORS);
    if (w.actors[i].status == ASL_A_READY)
    {
      slot = i;
      found = 1;
      break;
    }
  }
  if (!found)
    return w; /* idle: fixed point     */
  w.rr = (uint8_t)(slot + 1);

  AslActor *a = &w.actors[slot];
  asl_id id = (asl_id)(slot + 1);

  for (int step = 0; step < ASL_QUANTUM && a->status == ASL_A_READY; step++)
  {
    AslMsg m;
    memset(&m, 0, sizeof m);
    int has = a->count ? (m = mbox_pop(a), 1) : 0;

    AslStepOut r = a->fn(a->state, m, has); /* the pure call */

    switch ((AslStepKind)r.kind)
    {
    case ASL_S_CONTINUE:
      a->state = r.next;
      break;
    case ASL_S_WAITING:
      a->state = r.next;
      a->status = a->count ? ASL_A_READY : ASL_A_WAITING;
      return w;
    case ASL_S_DONE:
      terminate(&w, id, r.code);
      return w;
    case ASL_S_FAIL:
      terminate(&w, id, r.code);
      return w;
    }
  }
  return w;
}

/* Run quanta until no actor is READY. Termination: every step is a pure
 * bounded function and every actor either drains work or parks/exits. */
static AslWorld asl_run_to_idle(AslWorld w, int max_quanta)
{
  for (int q = 0; q < max_quanta; q++)
  {
    AslWorld w2 = asl_run_quantum(w);
    if (memcmp(&w2, &w, sizeof w) == 0)
      return w2; /* fixed point */
    w = w2;
  }
  return w;
}

static int asl_worlds_equal(AslWorld a, AslWorld b)
{
  return memcmp(&a, &b, sizeof a) == 0; /* values compare bitwise */
}
# actor.asl — pure functional actor runtime, translated from actor.c.

module Bool:
  union:
    False {}
    True {}

module MsgKind:
  union:
    User {}
    Stop {}
    Down {}

module AslMsg:
  struct:
    kind: MsgKind
    sender: u8
    tag: i32
    val: i32

  public func user(sender: u8, tag: i32, val: i32): AslMsg
    AslMsg { kind: MsgKind.User {}, sender: sender, tag: tag, val: val }

module AslState:
  struct:
    words: Array[i32]

  public func zero(): AslState
    AslState { words: Array[i32] { size: u32.from(Config.stateWords()) } }

module StepOut:
  union:
    Continue { next: AslState }
    Waiting { next: AslState }
    Done { code: i32 }
    Fail { code: i32 }

module ActorStatus:
  union:
    Free {}
    Ready {}
    Waiting {}
    Term {}

module Config:
  public func mboxCap(): u8       # user-mailbox ring size
    u8 6
  public func maxActors(): u8
    u8 8
  public func quantum(): u8
    u8 3
  public func stateWords(): u8   # i32 words in an AslState (the C's w[4])
    u8 4
  # The system ring is per-actor, sized `capacity + 1` at spawn (Behavior
  # fan-out + one Stop). No shared-ring reserve: user and system traffic
  # live in physically separate rings.

module PopResult:
  struct:
    msg: AslMsg
    actor: AslActor

# ---- outcome unions: legit results are VARIANTS; Err means impossible ----
module PushOut:
  union:
    Pushed { actor: AslActor }
    Full {}

module FindOut:
  union:
    Found { slot: u8 }
    NoneReady {}

module SpawnOut:
  union:
    Spawned { world: AslWorld, id: u8 }
    TableFull { world: AslWorld }

module AslActor:
  struct:
    state: AslState
    status: ActorStatus
    exitCode: i32
    parent: u8
    mbox: Array[AslMsg]       # user ring, size mboxCap
    head: u8
    count: u8
    sysMbox: Array[AslMsg]    # system ring (FIFO), size sysCap = capacity + 1
    sysHead: u8
    sysCount: u8
    sysCap: u8

  # push a USER message to the back of the user ring; Full = ring full.
  public func pushBack(actor: AslActor, m: AslMsg): PushOut!
    match u8.compare(actor.count, Config.mboxCap()):
      case 0:
        PushOut!.Ok { value: PushOut.Full {} }
      case _:
        sum = try u8.add(actor.head, actor.count)
        idx = u8.remainder(sum, Config.mboxCap())
        newMbox = try Array.set(actor.mbox, u32.from(idx), m)
        newCount = try u8.add(actor.count, u8 1)
        actor.mbox = newMbox
        actor.count = newCount
        PushOut!.Ok { value: PushOut.Pushed { actor: actor } }

  # push a SYSTEM message (Stop / Down) to the back of the system ring (FIFO).
  # Full should be UNREACHABLE when sysCap = Behavior.capacity + 1.
  public func pushSys(actor: AslActor, m: AslMsg): PushOut!
    match u8.compare(actor.sysCount, actor.sysCap):
      case 0:
        PushOut!.Ok { value: PushOut.Full {} }
      case _:
        sum = try u8.add(actor.sysHead, actor.sysCount)
        idx = u8.remainder(sum, actor.sysCap)
        newSys = try Array.set(actor.sysMbox, u32.from(idx), m)
        newCount = try u8.add(actor.sysCount, u8 1)
        actor.sysMbox = newSys
        actor.sysCount = newCount
        PushOut!.Ok { value: PushOut.Pushed { actor: actor } }

  public func pop(actor: AslActor): PopResult!
    m = try Array.get(actor.mbox, u32.from(actor.head))
    sum = try u8.add(actor.head, u8 1)
    newCount = try u8.subtract(actor.count, u8 1)
    actor.head = u8.remainder(sum, Config.mboxCap())
    actor.count = newCount
    PopResult!.Ok { value: PopResult { msg: m, actor: actor } }

  public func popSys(actor: AslActor): PopResult!
    m = try Array.get(actor.sysMbox, u32.from(actor.sysHead))
    sum = try u8.add(actor.sysHead, u8 1)
    newCount = try u8.subtract(actor.sysCount, u8 1)
    actor.sysHead = u8.remainder(sum, actor.sysCap)
    actor.sysCount = newCount
    PopResult!.Ok { value: PopResult { msg: m, actor: actor } }

  public func wake(actor: AslActor): AslActor
    match actor.status:
      case Waiting {}:
        actor.status = ActorStatus.Ready {}
        actor
      case _:
        actor

  # any pending message on either ring (system takes priority)
  public func hasWork(actor: AslActor): Bool
    match u8.compare(actor.sysCount, u8 0):
      case 1:
        Bool.True {}
      case _:
        match u8.compare(actor.count, u8 0):
          case 1:
            Bool.True {}
          case _:
            Bool.False {}

module SendResult:
  struct:
    world: AslWorld
    ok: Bool

module AslWorld:
  struct:
    actors: Array[AslActor]
    rr: u8

  public func empty(): AslWorld
    AslWorld { actors: Array[AslActor] { size: u32.from(Config.maxActors()) }, rr: u8 0 }

  # ---- indexed access (id is 1-based; slot = id - 1) ----
  public func getActor(world: AslWorld, id: u8): AslActor!
    match u8.subtract(id, u8 1):
      case Ok { value: idx }:
        Array.get(world.actors, u32.from(idx))
      case Err { error: e }:
        AslActor!.Err { error: e }

  public func setActor(world: AslWorld, id: u8, actor: AslActor): AslWorld!
    match u8.subtract(id, u8 1):
      case Ok { value: idx }:
        match Array.set(world.actors, u32.from(idx), actor):
          case Ok { value: newActors }:
            world.actors = newActors
            AslWorld!.Ok { value: world }
          case Err { error: e }:
            AslWorld!.Err { error: e }
      case Err { error: e }:
        AslWorld!.Err { error: e }

  public func alive(actor: AslActor): Bool
    match actor.status:
      case Free {}:
        Bool.False {}
      case Term {}:
        Bool.False {}
      case _:
        Bool.True {}

  # ---- terminate + parent notification (DOWN) ----
  # A dropped Down (parent mailbox full even with the reserve) is a real
  # supervision loss, so it surfaces as Err rather than a silent no-op.
  # An out-of-range parent index is impossible → also Err (loud).
  public func notifyParent(world: AslWorld, parentId: u8, childId: u8, code: i32): AslWorld!
    parent = try AslWorld.getActor(world, parentId)
    match AslWorld.alive(parent):
      case True {}:
        down = AslMsg { kind: MsgKind.Down {}, sender: childId, tag: code, val: i32 0 }
        pushed = try AslActor.pushSys(parent, down)
        match pushed:
          case Pushed { actor: parent1 }:
            awoken = AslActor.wake(parent1)
            AslWorld.setActor(world, parentId, awoken)
          case Full {}:
            # UNREACHABLE by the capacity theorem: sysCap = capacity+1
            # guarantees one DOWN slot per declared child. A Full here
            # means fan-out exceeded the declared capacity — a real
            # invariant violation, surfaced loudly, never dropped.
            AslWorld!.Err { error: Error { code: i32 5, message: string "system ring overflow: fan-out exceeded capacity" } }
      case False {}:
        AslWorld!.Ok { value: world }

  public func terminate(world: AslWorld, id: u8, code: i32): AslWorld!
    actor = try AslWorld.getActor(world, id)
    actor.status = ActorStatus.Term {}
    actor.exitCode = code
    world1 = try AslWorld.setActor(world, id, actor)
    match u8.compare(actor.parent, u8 0):
      case 0:
        AslWorld!.Ok { value: world1 }
      case _:
        AslWorld.notifyParent(world1, actor.parent, id, code)

  # ---- spawn: scan for the first FREE slot (recursive) ----
  # A full table is the TableFull variant (legit); an in-range index /
  # arithmetic failure is impossible, so it propagates loudly as Err.
  # sysCap sizes the new actor's system ring (= Behavior.capacity + 1); the
  # behavior-aware caller (Runtime.spawn) supplies it.
  public func spawn(world: AslWorld, parent: u8, init: AslState, sysCap: u8): SpawnOut!
    AslWorld.spawnFrom(world, parent, init, sysCap, u8 0)

  func spawnFrom(world: AslWorld, parent: u8, init: AslState, sysCap: u8, slot: u8): SpawnOut!
    match u8.compare(slot, Config.maxActors()):
      case -1:
        actor = try Array.get(world.actors, u32.from(slot))
        match actor.status:
          case Free {}:
            fresh = AslActor { state: init, status: ActorStatus.Ready {}, exitCode: i32 0, parent: parent, mbox: Array[AslMsg] { size: u32.from(Config.mboxCap()) }, head: u8 0, count: u8 0, sysMbox: Array[AslMsg] { size: u32.from(sysCap) }, sysHead: u8 0, sysCount: u8 0, sysCap: sysCap }
            id = try u8.add(slot, u8 1)
            world1 = try AslWorld.setActor(world, id, fresh)
            SpawnOut!.Ok { value: SpawnOut.Spawned { world: world1, id: id } }
          case _:
            next = try u8.add(slot, u8 1)
            AslWorld.spawnFrom(world, parent, init, sysCap, next)
      case _:
        SpawnOut!.Ok { value: SpawnOut.TableFull { world: world } }

  # ---- send: USER message to a live actor. Invalid target / backpressure
  # are legit Ok(ok: False); an impossible index failure propagates as Err. ----
  public func validTarget(world: AslWorld, to: u8): Bool
    match u8.compare(to, u8 0):
      case 0:
        Bool.False {}
      case _:
        match u8.compare(to, Config.maxActors()):
          case 1:
            Bool.False {}
          case _:
            match AslWorld.getActor(world, to):
              case Ok { value: actor }:
                AslWorld.alive(actor)
              case Err { error: e }:
                Bool.False {}

  public func send(world: AslWorld, from: u8, to: u8, tag: i32, val: i32): SendResult!
    match AslWorld.validTarget(world, to):
      case True {}:
        actor = try AslWorld.getActor(world, to)
        m = AslMsg { kind: MsgKind.User {}, sender: from, tag: tag, val: val }
        pushed = try AslActor.pushBack(actor, m)
        match pushed:
          case Pushed { actor: actor1 }:
            awoken = AslActor.wake(actor1)
            world1 = try AslWorld.setActor(world, to, awoken)
            SendResult!.Ok { value: SendResult { world: world1, ok: Bool.True {} } }
          case Full {}:
            SendResult!.Ok { value: SendResult { world: world, ok: Bool.False {} } }
      case False {}:
        SendResult!.Ok { value: SendResult { world: world, ok: Bool.False {} } }

  # Stop goes on the system ring (one reserved slot). Full is unreachable
  # by the capacity theorem → loud Err. Out-of-range index → Err.
  public func stop(world: AslWorld, id: u8): AslWorld!
    match AslWorld.validTarget(world, id):
      case True {}:
        actor = try AslWorld.getActor(world, id)
        m = AslMsg { kind: MsgKind.Stop {}, sender: u8 0, tag: i32 0, val: i32 0 }
        pushed = try AslActor.pushSys(actor, m)
        match pushed:
          case Pushed { actor: actor1 }:
            awoken = AslActor.wake(actor1)
            AslWorld.setActor(world, id, awoken)
          case Full {}:
            AslWorld!.Err { error: Error { code: i32 5, message: string "system ring overflow: fan-out exceeded capacity" } }
      case False {}:
        AslWorld!.Ok { value: world }

  public func kill(world: AslWorld, id: u8): AslWorld!
    match AslWorld.validTarget(world, id):
      case True {}:
        AslWorld.terminate(world, id, i32 -2)
      case False {}:
        AslWorld!.Ok { value: world }

  public func setRr(world: AslWorld, rr: u8): AslWorld
    world.rr = rr
    world

  # slot (0-based) of the next READY actor scanning round-robin from
  # `start`, having already checked `k` slots. Err = none ready (idle).
  public func findReady(world: AslWorld, start: u8, k: u8): FindOut!
    match u8.compare(k, Config.maxActors()):
      case -1:
        sum = try u8.add(start, k)
        i = u8.remainder(sum, Config.maxActors())
        actor = try Array.get(world.actors, u32.from(i))
        match actor.status:
          case Ready {}:
            FindOut!.Ok { value: FindOut.Found { slot: i } }
          case _:
            nextK = try u8.add(k, u8 1)
            AslWorld.findReady(world, start, nextK)
      case _:
        FindOut!.Ok { value: FindOut.NoneReady {} }

# ---- the actor behavior contract, as a generic ----
generic Behavior:
  func step(s: AslState, m: AslMsg, hasMsg: Bool): StepOut
  # Declared supervision fan-out: the max children this behavior spawns.
  # The system ring is sized `capacity + 1` (N guaranteed DOWN slots + 1
  # STOP), turning DOWN delivery into a compile-time capacity theorem.
  func capacity(): u8

# ---- a sample behavior (echo: park on any message, done when idle) ----
module Echo:
  struct:
    label: i32

  public func step(s: AslState, m: AslMsg, hasMsg: Bool): StepOut
    match hasMsg:
      case True {}:
        StepOut.Waiting { next: s }
      case False {}:
        StepOut.Done { code: i32 0 }

  public func capacity(): u8   # Echo spawns no children
    u8 0

# ---- scheduler: a world + the behavior all its actors run ----
module Runtime:
  struct(Behavior):
    world: AslWorld

  # spawn an actor whose system ring is sized by this behavior's declared
  # fan-out: sysCap = capacity + 1 (one DOWN slot per child, one for Stop).
  public func spawn(rt: Runtime[Behavior], parent: u8, init: AslState): SpawnOut!
    sysCap = try u8.add(Behavior.capacity(), u8 1)
    AslWorld.spawn(rt.world, parent, init, sysCap)

  # apply one pure step result to actor `id`, then keep stepping.
  func applyStep(rt: Runtime[Behavior], id: u8, actor: AslActor, m: AslMsg, has: Bool, steps: u8): Runtime[Behavior]!
    match Behavior.step(actor.state, m, has):
      case Continue { next: n }:
        actor.state = n
        world1 = try AslWorld.setActor(rt.world, id, actor)
        rt.world = world1
        rem = try u8.subtract(steps, u8 1)
        Runtime.runSteps(rt, id, rem)
      case Waiting { next: n }:
        actor.state = n
        match AslActor.hasWork(actor):
          case True {}:
            actor.status = ActorStatus.Ready {}
            world1 = try AslWorld.setActor(rt.world, id, actor)
            rt.world = world1
            Runtime[Behavior]!.Ok { value: rt }
          case False {}:
            actor.status = ActorStatus.Waiting {}
            world1 = try AslWorld.setActor(rt.world, id, actor)
            rt.world = world1
            Runtime[Behavior]!.Ok { value: rt }
      case Done { code: c }:
        world1 = try AslWorld.setActor(rt.world, id, actor)
        world2 = try AslWorld.terminate(world1, id, c)
        rt.world = world2
        Runtime[Behavior]!.Ok { value: rt }
      case Fail { code: c }:
        world1 = try AslWorld.setActor(rt.world, id, actor)
        world2 = try AslWorld.terminate(world1, id, c)
        rt.world = world2
        Runtime[Behavior]!.Ok { value: rt }

  # pop a message and apply one step. System ring drains first (priority);
  # then the user ring; else a message-less step (has = False).
  func runOne(rt: Runtime[Behavior], id: u8, actor: AslActor, steps: u8): Runtime[Behavior]!
    match u8.compare(actor.sysCount, u8 0):
      case 1:
        pr = try AslActor.popSys(actor)
        Runtime.applyStep(rt, id, pr.actor, pr.msg, Bool.True {}, steps)
      case _:
        match u8.compare(actor.count, u8 0):
          case 1:
            pr = try AslActor.pop(actor)
            Runtime.applyStep(rt, id, pr.actor, pr.msg, Bool.True {}, steps)
          case _:
            emptyMsg = AslMsg { kind: MsgKind.User {}, sender: u8 0, tag: i32 0, val: i32 0 }
            Runtime.applyStep(rt, id, actor, emptyMsg, Bool.False {}, steps)

  # run up to `steps` pure steps on actor `id`, stopping if it parks/exits.
  func runSteps(rt: Runtime[Behavior], id: u8, steps: u8): Runtime[Behavior]!
    match u8.compare(steps, u8 0):
      case 0:
        Runtime[Behavior]!.Ok { value: rt }
      case _:
        actor = try AslWorld.getActor(rt.world, id)
        match actor.status:
          case Ready {}:
            Runtime.runOne(rt, id, actor, steps)
          case _:
            Runtime[Behavior]!.Ok { value: rt }

  # one quantum: pick the next READY actor round-robin, run <= K steps.
  # A findReady Err means "no READY actor" — a legit idle fixed point (Ok).
  public func runQuantum(rt: Runtime[Behavior]): Runtime[Behavior]!
    world = rt.world
    found = try AslWorld.findReady(world, world.rr, u8 0)
    match found:
      case Found { slot: slot }:
        id = try u8.add(slot, u8 1)
        rt.world = AslWorld.setRr(rt.world, id)
        Runtime.runSteps(rt, id, Config.quantum())
      case NoneReady {}:
        Runtime[Behavior]!.Ok { value: rt }

  # run quanta until a fixed point (no READY actor) or the budget runs out.
  public func runToIdle(rt: Runtime[Behavior], maxQuanta: u32): Runtime[Behavior]!
    match u32.compare(maxQuanta, u32 0):
      case 1:
        next = try Runtime.runQuantum(rt)
        match Eq.world(rt.world, next.world):
          case True {}:
            Runtime[Behavior]!.Ok { value: next }
          case False {}:
            rem = try u32.subtract(maxQuanta, u32 1)
            Runtime.runToIdle(next, rem)
      case _:
        Runtime[Behavior]!.Ok { value: rt }

# ---- recursive structural equality (values compare deeply; C used memcmp) ----
module Eq:
  public func and(a: Bool, b: Bool): Bool
    match a:
      case True {}:
        b
      case False {}:
        Bool.False {}

  public func u8v(a: u8, b: u8): Bool
    match u8.compare(a, b):
      case 0:
        Bool.True {}
      case _:
        Bool.False {}

  public func i32v(a: i32, b: i32): Bool
    match i32.compare(a, b):
      case 0:
        Bool.True {}
      case _:
        Bool.False {}

  public func msgKind(a: MsgKind, b: MsgKind): Bool
    match a:
      case User {}:
        match b:
          case User {}:
            Bool.True {}
          case _:
            Bool.False {}
      case Stop {}:
        match b:
          case Stop {}:
            Bool.True {}
          case _:
            Bool.False {}
      case Down {}:
        match b:
          case Down {}:
            Bool.True {}
          case _:
            Bool.False {}

  public func status(a: ActorStatus, b: ActorStatus): Bool
    match a:
      case Free {}:
        match b:
          case Free {}:
            Bool.True {}
          case _:
            Bool.False {}
      case Ready {}:
        match b:
          case Ready {}:
            Bool.True {}
          case _:
            Bool.False {}
      case Waiting {}:
        match b:
          case Waiting {}:
            Bool.True {}
          case _:
            Bool.False {}
      case Term {}:
        match b:
          case Term {}:
            Bool.True {}
          case _:
            Bool.False {}

  public func msg(a: AslMsg, b: AslMsg): Bool
    Eq.and(Eq.msgKind(a.kind, b.kind), Eq.and(Eq.u8v(a.sender, b.sender), Eq.and(Eq.i32v(a.tag, b.tag), Eq.i32v(a.val, b.val))))

  public func words(a: Array[i32], b: Array[i32], i: u32, n: u32): Bool
    match u32.compare(i, n):
      case -1:
        match Array.get(a, i):
          case Ok { value: x }:
            match Array.get(b, i):
              case Ok { value: y }:
                match Eq.i32v(x, y):
                  case True {}:
                    match u32.add(i, u32 1):
                      case Ok { value: nextI }:
                        Eq.words(a, b, nextI, n)
                      case Err { error: e }:
                        Bool.False {}
                  case False {}:
                    Bool.False {}
              case Err { error: e }:
                Bool.False {}
          case Err { error: e }:
            Bool.False {}
      case _:
        Bool.True {}

  public func state(a: AslState, b: AslState): Bool
    Eq.words(a.words, b.words, u32 0, u32.from(Config.stateWords()))

  public func mbox(a: Array[AslMsg], b: Array[AslMsg], i: u32, n: u32): Bool
    match u32.compare(i, n):
      case -1:
        match Array.get(a, i):
          case Ok { value: x }:
            match Array.get(b, i):
              case Ok { value: y }:
                match Eq.msg(x, y):
                  case True {}:
                    match u32.add(i, u32 1):
                      case Ok { value: nextI }:
                        Eq.mbox(a, b, nextI, n)
                      case Err { error: e }:
                        Bool.False {}
                  case False {}:
                    Bool.False {}
              case Err { error: e }:
                Bool.False {}
          case Err { error: e }:
            Bool.False {}
      case _:
        Bool.True {}

  public func actor(a: AslActor, b: AslActor): Bool
    Eq.and(Eq.status(a.status, b.status), Eq.and(Eq.i32v(a.exitCode, b.exitCode), Eq.and(Eq.u8v(a.parent, b.parent), Eq.and(Eq.u8v(a.head, b.head), Eq.and(Eq.u8v(a.count, b.count), Eq.and(Eq.state(a.state, b.state), Eq.and(Eq.mbox(a.mbox, b.mbox, u32 0, u32.from(Config.mboxCap())), Eq.and(Eq.u8v(a.sysHead, b.sysHead), Eq.and(Eq.u8v(a.sysCount, b.sysCount), Eq.and(Eq.u8v(a.sysCap, b.sysCap), Eq.mbox(a.sysMbox, b.sysMbox, u32 0, u32.from(a.sysCap))))))))))))

  public func actors(a: Array[AslActor], b: Array[AslActor], i: u32, n: u32): Bool
    match u32.compare(i, n):
      case -1:
        match Array.get(a, i):
          case Ok { value: x }:
            match Array.get(b, i):
              case Ok { value: y }:
                match Eq.actor(x, y):
                  case True {}:
                    match u32.add(i, u32 1):
                      case Ok { value: nextI }:
                        Eq.actors(a, b, nextI, n)
                      case Err { error: e }:
                        Bool.False {}
                  case False {}:
                    Bool.False {}
              case Err { error: e }:
                Bool.False {}
          case Err { error: e }:
            Bool.False {}
      case _:
        Bool.True {}

  public func world(a: AslWorld, b: AslWorld): Bool
    Eq.and(Eq.u8v(a.rr, b.rr), Eq.actors(a.actors, b.actors, u32 0, u32.from(Config.maxActors())))

public module Driver:
  # spawn -> send -> run to idle, then ASSERT the expected end state.
  # Legit outcomes are matched variants (Spawned/TableFull, ok True/False);
  # an impossible path is a loud Err. Exit codes: 0 = as expected,
  # 1 = impossible-path Err, 2 = send rejected, 3 = actor didn't park,
  # 4 = spawn table full.
  public func start(): i32
    rt0 = Runtime[Echo] { world: AslWorld.empty() }
    match Runtime.spawn(rt0, u8 0, AslState.zero()):
      case Ok { value: spawnOut }:
        match spawnOut:
          case Spawned { world: w1, id: id }:
            match AslWorld.send(w1, u8 0, id, i32 7, i32 42):
              case Ok { value: sent }:
                match sent.ok:
                  case True {}:
                    rt = Runtime[Echo] { world: sent.world }
                    match Runtime.runToIdle(rt, u32 16):
                      case Ok { value: ran }:
                        Driver.assertParked(ran.world, id)
                      case Err { error: e }:
                        printed = System.println(e.message)
                        i32 1
                  case False {}:
                    printed = System.println(string "send was rejected")
                    i32 2
              case Err { error: e }:
                printed = System.println(e.message)
                i32 1
          case TableFull { world: w1 }:
            printed = System.println(string "spawn failed: table full")
            i32 4
      case Err { error: e }:
        printed = System.println(e.message)
        i32 1

  # Echo pops its one message and parks. At idle the actor MUST be WAITING
  # with a drained mailbox; anything else (still READY, terminated, backlog)
  # is a bug the runtime would otherwise idle past unnoticed.
  func assertParked(world: AslWorld, id: u8): i32
    match AslWorld.getActor(world, id):
      case Ok { value: actor }:
        parked = Eq.status(actor.status, ActorStatus.Waiting {})
        drained = Eq.u8v(actor.count, u8 0)
        match Eq.and(parked, drained):
          case True {}:
            i32 0
          case False {}:
            printed = System.println(string "actor did not park as expected")
            i32 3
      case Err { error: e }:
        printed = System.println(e.message)
        i32 1

# mini_actor6.asl — forced vs graceful control, translated from mini_actor6.c.
#
# Pure value semantics only: the pthreads/mutex/condvar layer is dropped.
# The mailbox + three rings + take-order are modelled world-in / world-out,
# the same shape used by actor.asl's scheduler.
#
# Urgent control jumps everything (no seq — "NOW"). Graceful control is
# merged with events in ARRIVAL ORDER via a sequence stamp: it waits for
# everything queued before it and nothing after it (a barrier).
#
# Codegen is disabled, so `asl build` printing [SUCCESS] means the program
# passed semantic analysis; it is not executed.

module Bool:
  union:
    False {}
    True {}

module Msg:
  struct:
    tag: i32
    val: i32

module Ctrl:
  struct:
    kind: i32
    arg: i32

# stamped variants: seq gives cross-ring arrival order
module SeqMsg:
  struct:
    seq: u64
    m: Msg

module SeqCtrl:
  struct:
    seq: u64
    c: Ctrl

module Config:
  public func eventCap(): u8
    u8 8
  public func ctrlCap(): u8
    u8 4
  public func urgentCap(): u8
    u8 2
  public func ctrlStop(): i32
    i32 0
  public func ctrlStat(): i32
    i32 1
  public func tagAdd(): i32
    i32 1

# ---- ring outcome unions: legit results are VARIANTS; Err = impossible ----
module EvtPush:
  union:
    Pushed { ring: EventRing }
    Full {}

module EvtPeek:
  union:
    Found { value: SeqMsg }
    Empty {}

module EvtPop:
  union:
    Popped { value: SeqMsg, ring: EventRing }
    Empty {}

module CtlPush:
  union:
    Pushed { ring: CtrlRing }
    Full {}

module CtlPeek:
  union:
    Found { value: SeqCtrl }
    Empty {}

module CtlPop:
  union:
    Popped { value: SeqCtrl, ring: CtrlRing }
    Empty {}

module UrgPush:
  union:
    Pushed { ring: UrgentRing }
    Full {}

module UrgPop:
  union:
    Popped { value: Ctrl, ring: UrgentRing }
    Empty {}

# ---- EventRing (SeqMsg, cap 8) ----
module EventRing:
  struct:
    buf: Array[SeqMsg]
    head: u8
    count: u8

  public func empty(): EventRing
    EventRing { buf: Array[SeqMsg] { size: u32.from(Config.eventCap()) }, head: u8 0, count: u8 0 }

  public func push(ring: EventRing, v: SeqMsg): EvtPush!
    match u8.compare(ring.count, Config.eventCap()):
      case 0:
        EvtPush!.Ok { value: EvtPush.Full {} }
      case _:
        sum = try u8.add(ring.head, ring.count)
        idx = u8.remainder(sum, Config.eventCap())
        newBuf = try Array.set(ring.buf, u32.from(idx), v)
        newCount = try u8.add(ring.count, u8 1)
        ring.buf = newBuf
        ring.count = newCount
        EvtPush!.Ok { value: EvtPush.Pushed { ring: ring } }

  public func peek(ring: EventRing): EvtPeek!
    match u8.compare(ring.count, u8 0):
      case 1:
        v = try Array.get(ring.buf, u32.from(ring.head))
        EvtPeek!.Ok { value: EvtPeek.Found { value: v } }
      case _:
        EvtPeek!.Ok { value: EvtPeek.Empty {} }

  public func pop(ring: EventRing): EvtPop!
    match u8.compare(ring.count, u8 0):
      case 1:
        v = try Array.get(ring.buf, u32.from(ring.head))
        sum = try u8.add(ring.head, u8 1)
        newCount = try u8.subtract(ring.count, u8 1)
        ring.head = u8.remainder(sum, Config.eventCap())
        ring.count = newCount
        EvtPop!.Ok { value: EvtPop.Popped { value: v, ring: ring } }
      case _:
        EvtPop!.Ok { value: EvtPop.Empty {} }

# ---- CtrlRing (SeqCtrl, cap 4) ----
module CtrlRing:
  struct:
    buf: Array[SeqCtrl]
    head: u8
    count: u8

  public func empty(): CtrlRing
    CtrlRing { buf: Array[SeqCtrl] { size: u32.from(Config.ctrlCap()) }, head: u8 0, count: u8 0 }

  public func push(ring: CtrlRing, v: SeqCtrl): CtlPush!
    match u8.compare(ring.count, Config.ctrlCap()):
      case 0:
        CtlPush!.Ok { value: CtlPush.Full {} }
      case _:
        sum = try u8.add(ring.head, ring.count)
        idx = u8.remainder(sum, Config.ctrlCap())
        newBuf = try Array.set(ring.buf, u32.from(idx), v)
        newCount = try u8.add(ring.count, u8 1)
        ring.buf = newBuf
        ring.count = newCount
        CtlPush!.Ok { value: CtlPush.Pushed { ring: ring } }

  public func peek(ring: CtrlRing): CtlPeek!
    match u8.compare(ring.count, u8 0):
      case 1:
        v = try Array.get(ring.buf, u32.from(ring.head))
        CtlPeek!.Ok { value: CtlPeek.Found { value: v } }
      case _:
        CtlPeek!.Ok { value: CtlPeek.Empty {} }

  public func pop(ring: CtrlRing): CtlPop!
    match u8.compare(ring.count, u8 0):
      case 1:
        v = try Array.get(ring.buf, u32.from(ring.head))
        sum = try u8.add(ring.head, u8 1)
        newCount = try u8.subtract(ring.count, u8 1)
        ring.head = u8.remainder(sum, Config.ctrlCap())
        ring.count = newCount
        CtlPop!.Ok { value: CtlPop.Popped { value: v, ring: ring } }
      case _:
        CtlPop!.Ok { value: CtlPop.Empty {} }

# ---- UrgentRing (Ctrl, cap 2 — no seq, order vs others is "NOW") ----
module UrgentRing:
  struct:
    buf: Array[Ctrl]
    head: u8
    count: u8

  public func empty(): UrgentRing
    UrgentRing { buf: Array[Ctrl] { size: u32.from(Config.urgentCap()) }, head: u8 0, count: u8 0 }

  public func push(ring: UrgentRing, v: Ctrl): UrgPush!
    match u8.compare(ring.count, Config.urgentCap()):
      case 0:
        UrgPush!.Ok { value: UrgPush.Full {} }
      case _:
        sum = try u8.add(ring.head, ring.count)
        idx = u8.remainder(sum, Config.urgentCap())
        newBuf = try Array.set(ring.buf, u32.from(idx), v)
        newCount = try u8.add(ring.count, u8 1)
        ring.buf = newBuf
        ring.count = newCount
        UrgPush!.Ok { value: UrgPush.Pushed { ring: ring } }

  public func pop(ring: UrgentRing): UrgPop!
    match u8.compare(ring.count, u8 0):
      case 1:
        v = try Array.get(ring.buf, u32.from(ring.head))
        sum = try u8.add(ring.head, u8 1)
        newCount = try u8.subtract(ring.count, u8 1)
        ring.head = u8.remainder(sum, Config.urgentCap())
        ring.count = newCount
        UrgPop!.Ok { value: UrgPop.Popped { value: v, ring: ring } }
      case _:
        UrgPop!.Ok { value: UrgPop.Empty {} }

# ---- taken item: a control message (with forced flag) or an event ----
module Item:
  union:
    CtrlItem { c: Ctrl, forced: Bool }
    EventItem { m: Msg }

module TakeOut:
  union:
    Took { item: Item, mbox: Mailbox }
    Idle {}

module PostOut:
  union:
    Posted { mbox: Mailbox }
    Rejected { mbox: Mailbox }

module Mailbox:
  struct:
    evt: EventRing
    ctl: CtrlRing
    urg: UrgentRing
    nextSeq: u64            # arrival clock

  public func empty(): Mailbox
    Mailbox { evt: EventRing.empty(), ctl: CtrlRing.empty(), urg: UrgentRing.empty(), nextSeq: u64 0 }

  # edges: post an event, stamped with the arrival seq (which then advances).
  # A full ring is a capacity-design error for this bounded demo -> loud Err.
  public func postEvent(mbox: Mailbox, m: Msg): Mailbox!
    pout = try EventRing.push(mbox.evt, SeqMsg { seq: mbox.nextSeq, m: m })
    match pout:
      case Pushed { ring: newEvt }:
        mbox.evt = newEvt
        newSeq = try u64.add(mbox.nextSeq, u64 1)
        mbox.nextSeq = newSeq
        Mailbox!.Ok { value: mbox }
      case Full {}:
        Mailbox!.Err { error: Error { code: i32 1, message: string "event ring full" } }

  # graceful control: stamped like an event so it merges in arrival order.
  public func postCtrl(mbox: Mailbox, c: Ctrl): Mailbox!
    pout = try CtrlRing.push(mbox.ctl, SeqCtrl { seq: mbox.nextSeq, c: c })
    match pout:
      case Pushed { ring: newCtl }:
        mbox.ctl = newCtl
        newSeq = try u64.add(mbox.nextSeq, u64 1)
        mbox.nextSeq = newSeq
        Mailbox!.Ok { value: mbox }
      case Full {}:
        Mailbox!.Err { error: Error { code: i32 2, message: string "ctrl ring full" } }

  # forced control: NO seq bump — it is not part of arrival order.
  public func postUrgent(mbox: Mailbox, c: Ctrl): Mailbox!
    pout = try UrgentRing.push(mbox.urg, c)
    match pout:
      case Pushed { ring: newUrg }:
        mbox.urg = newUrg
        Mailbox!.Ok { value: mbox }
      case Full {}:
        Mailbox!.Err { error: Error { code: i32 3, message: string "urgent ring full" } }

  # take: urgent first; else the OLDEST of {graceful ctrl, event} by seq.
  public func take(mbox: Mailbox): TakeOut!
    uout = try UrgentRing.pop(mbox.urg)
    match uout:
      case Popped { value: uc, ring: newUrg }:
        mbox.urg = newUrg
        TakeOut!.Ok { value: TakeOut.Took { item: Item.CtrlItem { c: uc, forced: Bool.True {} }, mbox: mbox } }
      case Empty {}:
        Mailbox.takeMerged(mbox)

  # no urgent traffic: merge graceful ctrl and events by arrival seq.
  public func takeMerged(mbox: Mailbox): TakeOut!
    cpeek = try CtrlRing.peek(mbox.ctl)
    mpeek = try EventRing.peek(mbox.evt)
    Mailbox.decide(mbox, cpeek, mpeek)

  public func decide(mbox: Mailbox, cpeek: CtlPeek, mpeek: EvtPeek): TakeOut!
    match cpeek:
      case Found { value: hc }:
        match mpeek:
          case Found { value: hm }:
            # both present: take ctrl iff it is older (hc.seq < hm.seq),
            # i.e. compare(hm.seq, hc.seq) == 1. Seqs are unique.
            cseq = hc.seq
            mseq = hm.seq
            match u64.compare(mseq, cseq):
              case 1:
                Mailbox.takeCtrl(mbox)
              case _:
                Mailbox.takeEvent(mbox)
          case Empty {}:
            Mailbox.takeCtrl(mbox)
      case Empty {}:
        match mpeek:
          case Found { value: hm }:
            Mailbox.takeEvent(mbox)
          case Empty {}:
            TakeOut!.Ok { value: TakeOut.Idle {} }

  public func takeCtrl(mbox: Mailbox): TakeOut!
    pout = try CtrlRing.pop(mbox.ctl)
    match pout:
      case Popped { value: sc, ring: newCtl }:
        mbox.ctl = newCtl
        inner = sc.c
        TakeOut!.Ok { value: TakeOut.Took { item: Item.CtrlItem { c: inner, forced: Bool.False {} }, mbox: mbox } }
      case Empty {}:
        TakeOut!.Ok { value: TakeOut.Idle {} }

  public func takeEvent(mbox: Mailbox): TakeOut!
    pout = try EventRing.pop(mbox.evt)
    match pout:
      case Popped { value: sm, ring: newEvt }:
        mbox.evt = newEvt
        inner = sm.m
        TakeOut!.Ok { value: TakeOut.Took { item: Item.EventItem { m: inner }, mbox: mbox } }
      case Empty {}:
        TakeOut!.Ok { value: TakeOut.Idle {} }

# ---- Actor: a summer. state is the running sum; exitCode tracks it. ----
module Actor:
  struct:
    mbox: Mailbox
    sum: i32
    exitCode: i32
    done: Bool

  public func fresh(mbox: Mailbox): Actor
    Actor { mbox: mbox, sum: i32 0, exitCode: i32 0, done: Bool.False {} }

  # one loop iteration: take an item and apply it.
  public func step(actor: Actor): Actor!
    tout = try Mailbox.take(actor.mbox)
    match tout:
      case Idle {}:
        actor.done = Bool.True {}
        Actor!.Ok { value: actor }
      case Took { item: it, mbox: newMbox }:
        actor.mbox = newMbox
        Actor.apply(actor, it)

  public func apply(actor: Actor, it: Item): Actor!
    match it:
      case CtrlItem { c: c, forced: forced }:
        match i32.compare(c.kind, Config.ctrlStop()):
          case 0:
            # STOP. Forced stop abandons the backlog; graceful stop, by
            # arrival order, means everything queued before it already ran.
            actor.done = Bool.True {}
            Actor!.Ok { value: actor }
          case _:
            # STAT (or any other control): observe, keep going.
            Actor!.Ok { value: actor }
      case EventItem { m: m }:
        match i32.compare(m.tag, Config.tagAdd()):
          case 0:
            newSum = try i32.add(actor.sum, m.val)
            actor.sum = newSum
            actor.exitCode = newSum
            Actor!.Ok { value: actor }
          case _:
            Actor!.Ok { value: actor }

  # run the loop to completion (self-recursion; bounded by the backlog).
  public func run(actor: Actor): Actor!
    match actor.done:
      case True {}:
        Actor!.Ok { value: actor }
      case False {}:
        stepped = try Actor.step(actor)
        Actor.run(stepped)

# ---- deep equals (structural, recursive) for testing worlds ----
module Eq:
  public func and(a: Bool, b: Bool): Bool
    match a:
      case True {}:
        b
      case False {}:
        Bool.False {}

  public func i32v(a: i32, b: i32): Bool
    match i32.compare(a, b):
      case 0:
        Bool.True {}
      case _:
        Bool.False {}

  public func u8v(a: u8, b: u8): Bool
    match u8.compare(a, b):
      case 0:
        Bool.True {}
      case _:
        Bool.False {}

  public func u64v(a: u64, b: u64): Bool
    match u64.compare(a, b):
      case 0:
        Bool.True {}
      case _:
        Bool.False {}

  public func msg(a: Msg, b: Msg): Bool
    Eq.and(Eq.i32v(a.tag, b.tag), Eq.i32v(a.val, b.val))

  public func ctrl(a: Ctrl, b: Ctrl): Bool
    Eq.and(Eq.i32v(a.kind, b.kind), Eq.i32v(a.arg, b.arg))

  public func actor(a: Actor, b: Actor): Bool
    Eq.and(Eq.i32v(a.sum, b.sum), Eq.i32v(a.exitCode, b.exitCode))

# ---- demo: same backlog, two stop semantics ----
module Driver:
  # preload the whole scenario: events 1..3, graceful STAT, events 4..5,
  # then a STOP (urgent if forced, else graceful). Arrival order is fixed.
  public func buildBacklog(forced: Bool): Mailbox!
    m1 = try Mailbox.postEvent(Mailbox.empty(), Msg { tag: Config.tagAdd(), val: i32 1 })
    m2 = try Mailbox.postEvent(m1, Msg { tag: Config.tagAdd(), val: i32 2 })
    m3 = try Mailbox.postEvent(m2, Msg { tag: Config.tagAdd(), val: i32 3 })
    m4 = try Mailbox.postCtrl(m3, Ctrl { kind: Config.ctrlStat(), arg: i32 0 })
    m5 = try Mailbox.postEvent(m4, Msg { tag: Config.tagAdd(), val: i32 4 })
    m6 = try Mailbox.postEvent(m5, Msg { tag: Config.tagAdd(), val: i32 5 })
    Driver.postStop(m6, forced)

  public func postStop(mbox: Mailbox, forced: Bool): Mailbox!
    match forced:
      case True {}:
        Mailbox.postUrgent(mbox, Ctrl { kind: Config.ctrlStop(), arg: i32 0 })
      case False {}:
        Mailbox.postCtrl(mbox, Ctrl { kind: Config.ctrlStop(), arg: i32 0 })

  # run one scenario, return the final accumulated sum:
  #   graceful (forced = False) drains all 5 events -> 15
  #   forced   (forced = True)  jumps the backlog   -> 0
  public func runScenario(forced: Bool): i32!
    mbox = try Driver.buildBacklog(forced)
    final = try Actor.run(Actor.fresh(mbox))
    i32!.Ok { value: final.sum }

  # entry point: exercise both stop semantics; return the graceful sum (15).
  public func start(): i32
    match Driver.runScenario(Bool.False {}):
      case Ok { value: gracefulSum }:
        match Driver.runScenario(Bool.True {}):
          case Ok { value: forcedSum }:
            gracefulSum
          case Err { error: e }:
            i32 254
      case Err { error: e }:
        i32 255

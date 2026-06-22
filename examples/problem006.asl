import { u8, u64, Array, Status, Any, Error, Bitset, System } from "base.asl"
# Project Euler #6 style exercise — closed-form arithmetic. The
# simplest example that exercises only primitive literal
# initializers (u64 100) and primitive method calls without any
# match, data blocks, or recursion.
public module Solver:
  func start(): u8
    n = u64 100
    match u64.subtract(n, 1):
      case Ok { value: a }:
        match u64.add(n, 1):
          case Ok { value: b }:
            match u64.multiply(n, 3):
              case Ok { value: c }:
                match u64.add(c, 2):
                  case Ok { value: d }:
                    match u64.multiply(a, b):
                      case Ok { value: e }:
                        match u64.multiply(e, d):
                          case Ok { value: f }:
                            match u64.multiply(n, f):
                              case Ok { value: g }:
                                match u64.quotient(g, 12):
                                  case Ok { value: h }:
                                    u8 0
                                  case _:
                                    u8 1
                              case _:
                                u8 1
                          case _:
                            u8 1
                      case _:
                        u8 1
                  case _:
                    u8 1
              case _:
                u8 1
          case _:
            u8 1
      case _:
        u8 1

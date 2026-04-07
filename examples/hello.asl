import { Sample } from "../sample.asl"

generic Key:
  func hash(key: Key): u128

@export
module App:
  @export
  func start(sys: System): u8
    System.println("Hello, world!")

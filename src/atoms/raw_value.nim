import location

type RawValue* = ref object of RootObj
  value: string
  location: Location

proc value*(raw_value: RawValue): string = raw_value.value
proc location*(raw_value: RawValue): Location = raw_value.location
proc `$`*(raw_value: RawValue): string = raw_value.value

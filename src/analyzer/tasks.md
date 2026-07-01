- [x] Tell me what is the role of every single markdown file.

- [x] Change the `aslb` file prefix to `aslr` representing asl runtime file.

- [x] Re-enable the exact floating point value check but don't return error instead print it as warning that the closest approximate value will be used.

- [ ] In import statements adding `.asl` suffix in the file name is optional the compiler will resolve the path if the file is not found then it would check the same path with auto appened `.asl` suffix

- [ ] Change the vendor specification from `@<vendor_name>` to `<vendor_name>:<some_path>` so `asl:base` and vendor_path cmd line args format renames same but lookup mechanism changes from that exact path to `<path_to_vendor_named_asl>/base`
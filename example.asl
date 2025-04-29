# print demo
a = S64 435218769
_ = S64.unsafe_print(a)

b = F64 3.14159
_ = F64.unsafe_print(b)

# integer addition
c = S64.unsafe_add(a, a)
_ = S64.unsafe_print(c)

# float addition
d = F64.unsafe_add(b, b)
_ = F64.unsafe_print(d)

# integer to float conversion
e = F64.unsafe_from(a)
f = F64.unsafe_add(b, e)
_ = F64.unsafe_print(f)

# float to integer conversion
g = S64.unsafe_from(b)
h = S64.unsafe_add(a, g)
_ = S64.unsafe_print(h)

i = S64 235989
j = S64 31242

# bitwise or
k = S64.or(i, j)
_ = S64.unsafe_print(k)

# bitwise and
l = S64.and(i, j)
_ = S64.unsafe_print(l)

# bitwise xor
m = S64.xor(i, j)
_ = S64.unsafe_print(m)

n = S64 3

# bitwise left shift
o = S64.lshift(i, n)
_ = S64.unsafe_print(o)

# bitwise right shift
p = S64.rshift(i, n)
_ = S64.unsafe_print(p)

# bitwise not
r = S64.not(n)
_ = S64.unsafe_print(r)

fn sum return S64:
  args(S64 x):
    S64.unsafe_add(x, 1)
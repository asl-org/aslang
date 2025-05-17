#ifndef ASL_BITSET_H
#define ASL_BITSET_H

#include <stdlib.h>

#include "base.h"

#include "bitset.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define WORD_SIZE 64

typedef struct
{
  U64 *data;
  U64 bits;
} Bitset;

Bitset Bitset_init(U64 bits)
{
  Bitset bs;
  bs.bits = bits;

  // Allocate memory and fill it with zeros
  U64 capacity = ((bits + WORD_SIZE - 1) / WORD_SIZE) * sizeof(U64);
  bs.data = (U64 *)malloc(capacity);
  memset(bs.data, 0, capacity);

  return bs;
}

U64 Bitset_free(Bitset *bs)
{
  if (bs->data)
  {
    free(bs->data);
    bs->data = NULL;
  }

  U64 capacity = ((bs->bits + WORD_SIZE - 1) / WORD_SIZE) * sizeof(U64);
  bs->bits = 0;
  return capacity;
}

U8 Bitset_get(const Bitset *bs, U64 bit)
{
  return bit < bs->bits
             ? (bs->data[bit / WORD_SIZE] >> (bit % WORD_SIZE)) & 1
             : 0;
}

Bitset *Bitset_set(Bitset *bs, U64 bit)
{
  if (bit >= bs->bits)
    return bs;

  bs->data[bit / WORD_SIZE] |= ((U64)1 << (bit % WORD_SIZE));
  return bs;
}

Bitset *Bitset_unset(Bitset *bs, U64 bit)
{
  if (bit >= bs->bits)
    return bs;

  bs->data[bit / WORD_SIZE] &= ~((U64)1 << (bit % WORD_SIZE));
  return bs;
}

Bitset *Bitset_toggle(Bitset *bs, U64 bit)
{
  if (bit >= bs->bits)
    return bs;

  return Bitset_get(bs, bit) ? Bitset_unset(bs, bit) : Bitset_set(bs, bit);
}

U64 Bitset_print(const Bitset *bs)
{
  U64 ans = 0;

  for (U64 i = 0; i < bs->bits; ++i)
  {
    ans += printf("%d", Bitset_get(bs, i));
    if ((i + 1) % 8 == 0)
      ans += printf(" ");
  }

  ans += printf("\n");
  return ans;
}

#endif // ASL_BITSET_H
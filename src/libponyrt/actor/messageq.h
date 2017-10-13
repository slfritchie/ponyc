#ifndef messageq_h
#define messageq_h

#include "../pony.h"
#include <platform.h>

PONY_EXTERN_C_BEGIN

typedef struct messageq_t
{
  PONY_ATOMIC(pony_msg_t*) head;
  pony_msg_t* tail;
} messageq_t;

/* Hide the casting of arg #1 and #2 from calling code */
#define PONYINT_MESSAGEQ_PUSH(sched, from_actor, to_actor, q, first, last) \
    ponyint_messageq_push((uintptr_t) (sched), \
      (uintptr_t) (from_actor), (uintptr_t) (to_actor), (q), (first), (last))
#define PONYINT_MESSAGEQ_PUSH_SINGLE(sched, from_actor, to_actor, q, first, last) \
    ponyint_messageq_push_single((uintptr_t) (sched), \
      (uintptr_t) (from_actor), (uintptr_t) (to_actor), (q), (first), (last))
#define PONYINT_MESSAGEQ_POP(sched, actor, q) \
    ponyint_messageq_pop((uintptr_t) (sched), (uintptr_t) (actor), (q))

void ponyint_messageq_init(messageq_t* q);

void ponyint_messageq_destroy(messageq_t* q);

bool ponyint_messageq_push(uintptr_t sched,
     uintptr_t from_actor, uintptr_t to_actor, messageq_t* q,
     pony_msg_t* first, pony_msg_t* last);

bool ponyint_messageq_push_single(uintptr_t sched,
     uintptr_t from_actor, uintptr_t to_actor, messageq_t* q,
     pony_msg_t* first, pony_msg_t* last);

pony_msg_t* ponyint_messageq_pop(uintptr_t sched, uintptr_t actor,
  messageq_t* q);

bool ponyint_messageq_markempty(messageq_t* q);

PONY_EXTERN_C_END

#endif

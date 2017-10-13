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

#define Q_TYPE_THREAD 42
#define Q_TYPE_ACTOR  43

/* Hide the casting of arg #1 and #2 from calling code */
#define PONYINT_MESSAGEQ_PUSH(sched, from_actor, to_actor, q, first, last) \
    ponyint_messageq_push(Q_TYPE_ACTOR, (uintptr_t) (sched),            \
      (uintptr_t) (from_actor), (uintptr_t) (to_actor), (q), (first), (last))
#define PONYINT_MESSAGEQ_PUSH_SINGLE(sched, from_actor, to_actor, q, first, last) \
    ponyint_messageq_push_single(Q_TYPE_ACTOR, (uintptr_t) (sched), \
      (uintptr_t) (from_actor), (uintptr_t) (to_actor), (q), (first), (last))
#define PONYINT_MESSAGEQ_POP(sched, actor, q) \
    ponyint_messageq_pop(Q_TYPE_ACTOR, (uintptr_t) (sched), (uintptr_t) (actor), (q))
#define THREAD_PONYINT_MESSAGEQ_PUSH(from_index, to_index, q, first, last) \
    ponyint_messageq_push(Q_TYPE_THREAD, 0, \
      (uintptr_t) (from_index), (uintptr_t) (to_index), (q), (first), (last))
#define THREAD_PONYINT_MESSAGEQ_PUSH_SINGLE(from_index, to_index, q, first, last) \
    ponyint_messageq_push_single(Q_TYPE_THREAD, 0, \
      (uintptr_t) (from_index), (uintptr_t) (to_index), (q), (first), (last))
#define THREAD_PONYINT_MESSAGEQ_POP(index, q) \
    ponyint_messageq_pop(Q_TYPE_THREAD, 0, (uintptr_t) (index), (q))

void ponyint_messageq_init(messageq_t* q);

void ponyint_messageq_destroy(messageq_t* q);

bool ponyint_messageq_push(int caller_type, uintptr_t sched,
       uintptr_t from_actor, uintptr_t to_actor, messageq_t* q,
       pony_msg_t* first, pony_msg_t* last);

bool ponyint_messageq_push_single(int caller_type, uintptr_t sched,
       uintptr_t from_actor, uintptr_t to_actor, messageq_t* q,
       pony_msg_t* first, pony_msg_t* last);

pony_msg_t* ponyint_messageq_pop(int caller_type, uintptr_t sched,
              uintptr_t actor, messageq_t* q);

bool ponyint_messageq_markempty(messageq_t* q);

PONY_EXTERN_C_END

#endif

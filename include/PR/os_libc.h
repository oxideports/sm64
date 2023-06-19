#ifndef _OS_LIBC_H_
#define _OS_LIBC_H_

#include "libultra/ultratypes.h"

#if defined(__APPLE__)
#include <strings.h>
#else
// Old deprecated functions from strings.h, replaced by memcpy/memset.
extern void bcopy(const void *, void *, size_t);
extern void bzero(void *, size_t);
#endif

#endif /* !_OS_LIBC_H_ */

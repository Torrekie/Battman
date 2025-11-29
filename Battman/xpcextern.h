//
//  xpcextern.h
//  Battman
//
//  Created by Torrekie on 2025/11/27.
//

#ifndef xpcextern_h
#define xpcextern_h

#if __has_include(<xpc/xpc.h>)
#include <xpc/xpc.h>
#else
#include <os/base.h>
#include <os/object.h>
#include <dispatch/dispatch.h>

#ifdef __OBJC__
OS_OBJECT_DECL(xpc_object);
#define XPC_DECL(name) typedef xpc_object_t name##_t
#define XPC_GLOBAL_OBJECT(object) ((OS_OBJECT_BRIDGE xpc_object_t)&(object))
#else
typedef void * xpc_object_t;
#define XPC_DECL(name) typedef struct _##name##_s * name##_t
#define XPC_GLOBAL_OBJECT(object) (&(object))
#endif

typedef const struct _xpc_type_s * xpc_type_t;
#ifndef XPC_TYPE
#define XPC_TYPE(type) const struct _xpc_type_s type
#endif // XPC_TYPE
#define XPC_EXPORT extern __attribute__((visibility("default")))

#if __BLOCKS__
typedef void (^xpc_handler_t)(xpc_object_t object);
#endif // __BLOCKS__

#define XPC_TYPE_DICTIONARY (&_xpc_type_dictionary)
XPC_EXPORT
XPC_TYPE(_xpc_type_dictionary);
#define XPC_TYPE_CONNECTION (&_xpc_type_connection)
XPC_EXPORT
XPC_TYPE(_xpc_type_connection);
XPC_DECL(xpc_connection);
#define XPC_TYPE_ERROR (&_xpc_type_error)
XPC_EXPORT
XPC_TYPE(_xpc_type_error);

#define XPC_ERROR_CONNECTION_INTERRUPTED \
XPC_GLOBAL_OBJECT(_xpc_error_connection_interrupted)
XPC_EXPORT
const struct _xpc_dictionary_s _xpc_error_connection_interrupted;
#define XPC_ERROR_CONNECTION_INVALID \
XPC_GLOBAL_OBJECT(_xpc_error_connection_invalid)
XPC_EXPORT
const struct _xpc_dictionary_s _xpc_error_connection_invalid;

#define XPC_ERROR_KEY_DESCRIPTION _xpc_error_key_description
XPC_EXPORT
const char * const _xpc_error_key_description;

#define XPC_CONNECTION_MACH_SERVICE_LISTENER (1 << 0)
#define XPC_CONNECTION_MACH_SERVICE_PRIVILEGED (1 << 1)

__BEGIN_DECLS

xpc_type_t xpc_get_type(xpc_object_t object);
int64_t xpc_dictionary_get_int64(xpc_object_t xdict, const char *key);
xpc_object_t xpc_dictionary_create_reply(xpc_object_t original);
void xpc_dictionary_set_int64(xpc_object_t xdict, const char *key, int64_t value);
void xpc_connection_send_message(xpc_connection_t connection, xpc_object_t message);
void xpc_release(xpc_object_t object);
xpc_object_t xpc_dictionary_create(const char *const *keys, xpc_object_t const *values, size_t count);
void xpc_connection_resume(xpc_connection_t connection);
void xpc_dictionary_set_data(xpc_object_t xdict, const char *key, const void *bytes, size_t length);
void xpc_connection_set_event_handler(xpc_connection_t connection, xpc_handler_t handler);
xpc_connection_t xpc_connection_create_mach_service(const char *name, dispatch_queue_t targetq, uint64_t flags);
void xpc_connection_set_event_handler(xpc_connection_t connection, xpc_handler_t handler);
const char * xpc_dictionary_get_string(xpc_object_t xdict, const char *key);
void xpc_connection_cancel(xpc_connection_t connection);
xpc_object_t xpc_connection_send_message_with_reply_sync(xpc_connection_t connection, xpc_object_t message);

__END_DECLS

#endif
#endif /* xpcextern_h */

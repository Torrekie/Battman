#pragma once

#include <objc/objc.h>
#include <objc/runtime.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>

#include "cpp_magic.h"

#define oclass(cls) \
	({Class v;asm("adrp %0,_OBJC_CLASS_$_" #cls "@GOTPAGE \n" \
			"ldr %0,[%0,_OBJC_CLASS_$_" #cls "@GOTPAGEOFF]":"=r"(v));v;})

#define oselector(sel) \
	({SEL v;asm("adrp %0,\"oselector::" #sel "!%=\"@PAGE \n" \
		"ldr %0,[%0,\"oselector::" #sel "!%=\"@PAGEOFF] \n " \
		".section __TEXT,__objc_methname,cstring_literals \n" \
		"\"oselector~meth::" #sel "!%=\": .asciz \"" #sel "\" \n" \
		".section __DATA,__objc_selrefs,literal_pointers,no_dead_strip \n" \
		"\"oselector::" #sel "!%=\": .quad \"oselector~meth::" #sel "!%=\" \n" \
		".section __TEXT,__text,regular,pure_instructions":"=r"(v));v;})

void objc_release(id);
id objc_retain(id);
id objc_alloc(Class);
id objc_alloc_init(Class);
BOOL objc_opt_isKindOfClass(id,Class);
BOOL class_respondsToSelector(Class,SEL);

static const uint64_t _block_descriptor_1arg[2]={0,40};
#define objc_make_block(func,context) \
	({uint64_t blk_content[40]; \
		blk_content[0]=(uint64_t)&_NSConcreteStackBlock; \
		blk_content[1]=0x60000000; \
		blk_content[2]=(uint64_t)func; \
		blk_content[3]=(uint64_t)&_block_descriptor_1arg; \
		blk_content[4]=(uint64_t)context; \
		id blk=object_copy((id)&blk_content,40); \
		blk;})

extern void objc_msgSend(void);
extern void objc_msgSendSuper(void);

#define _ocall_type_expand_r(val,...) ,typeof(val) IF(HAS_ARGS(__VA_ARGS__)) ( DEFER2(_ocall_type_expand_)()(__VA_ARGS__) )
#define _ocall_type_expand_() _ocall_type_expand_r
#define _ocall_type_expand(...) IF(HAS_ARGS(__VA_ARGS__)) ( EVAL(_ocall_type_expand_r(__VA_ARGS__)) )
#define _ocall_name_expand_r(val,...) ,val IF(HAS_ARGS(__VA_ARGS__)) ( DEFER2(_ocall_name_expand_)()(__VA_ARGS__) )
#define _ocall_name_expand_() _ocall_name_expand_r
#define _ocall_name_expand(...) IF(HAS_ARGS(__VA_ARGS__)) ( EVAL(_ocall_name_expand_r(__VA_ARGS__)) )

#define _ocall_t(ret_type,send,obj,sel,...) ((ret_type(*)(typeof(obj),SEL _ocall_type_expand(__VA_ARGS__)))send)(obj,oselector(sel) _ocall_name_expand(__VA_ARGS__))

#define ocall(...) _ocall_t(void*,objc_msgSend,__VA_ARGS__,)
#define ocall_t(ret_type,...) _ocall_t(ret_type,objc_msgSend,__VA_ARGS__,)


#include "./cobjc_types.h"
#include "./cobjc_class.h"

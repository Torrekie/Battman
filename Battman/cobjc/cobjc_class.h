#pragma once

#define DEFINE_CLASS(name, superclass, context_length) \
	asm(".section __DATA,__objc_data\n" \
		".globl _OBJC_CLASS_$_" #name "\n" \
		".p2align 3\n" \
		"_OBJC_CLASS_$_" #name ":\n" \
		".quad _OBJC_METACLASS_$_" #name "\n" \
		".quad _OBJC_CLASS_$_" #superclass "\n" \
		".quad __objc_empty_cache\n.quad 0\n" \
		".quad __OBJC_CLASS_RO_$_" #name "\n" \
		".globl _OBJC_METACLASS_$_" #name "\n" \
		"_OBJC_METACLASS_$_" #name ":\n" \
		".quad _OBJC_METACLASS_$_NSObject\n" \
		".quad _OBJC_METACLASS_$_" #superclass "\n" \
		".quad __objc_empty_cache\n.quad 0\n" \
		".quad __OBJC_METACLASS_RO_$_" #name "\n" \
		".section __DATA,__objc_superrefs,regular,no_dead_strip\n" \
		".p2align 3\n" \
		"l_suprefs_" #name ": .quad _OBJC_CLASS_$_" #name "\n" \
		".section __DATA,__objc_classlist,regular,no_dead_strip\n" \
		".p2align 3\nl_objc_label_" #name ": .quad _OBJC_CLASS_$_" #name "\n" \
		".section __DATA,__objc_const\n" \
		"__OBJC_CLASS_RO_$_" #name ":\n" \
		".long 0\n.long 8\n.long " #context_length "+8\n.space 4\n.quad 0\n" \
		".quad l$$classname$$" #name "\n" \
		".quad _instance_methods." #name ".objc\n" \
		".quad 0\n.quad _instance_vars." #name ".objc\n" \
		".quad 0\n.quad 0\n" \
		"__OBJC_METACLASS_RO_$_" #name ":\n" \
		".long 1\n.long 40\n.long 40\n.space 4\n.quad 0\n" \
		".quad l$$classname$$" #name "\n" \
		".quad _class_methods." #name ".objc\n" \
		".quad 0\n.quad 0\n.quad 0\n.quad 0\n" \
		"_instance_vars." #name ".objc:\n" \
		".long 32\n.long 1\n.quad _OBJC_IVAR_$_" #name ".cobjc_struct\n" \
		".quad l_objc_ivar_name_" #name "\n.quad l_objc_ivar_type_" #name "\n.long 3\n" \
		".long " #context_length "\n" \
		".section __DATA,__objc_ivar\n.globl _OBJC_IVAR_$_" #name ".cobjc_struct\n" \
		".p2align 2\n_OBJC_IVAR_$_" #name ".cobjc_struct:\n" \
		".long 8\n" \
		".section __TEXT,__objc_methname,cstring_literals\n" \
		"l_objc_ivar_name_" #name ": .asciz \"cobjc_struct_" #name "\"\n" \
		"l_objc_ivar_type_" #name ": .asciz \"{unk=?}\"\n" \
		"l$$classname$$" #name ": .asciz \"" #name "\"\n")

#define _MAKE_NUM(num) #num
#define MAKE_NUM(...) _MAKE_NUM(__VA_ARGS__)

#define _DEFINE_CLASS_METHODS(class, count) \
	asm(".section __DATA,__objc_const\n" \
		".p2align 3\n_class_methods." #class ".objc:\n.long 24\n" \
		".long " count "\n")
#define DEFINE_CLASS_METHODS(class,count) _DEFINE_CLASS_METHODS(class,#count)
// type doesn't really matter I think
// Selector is replaced by customized struct ptr
// Ivar is retrieved from class_rw_t dynamically
// bc I can't find a way to reference _OBJC_IVAR_$_classname
// without adding an extra argument to this macro..
// For class methods, x1 (arg2) is untouched and remains to be the selector.
#define ADD_METHOD_WITH_TYPE(class,func,selector,type) \
	asm(".quad l_cls_method_name_" #func "_\n" \
		".quad l_cls_method_type_" #func "_\n"\
		".quad \"cobjc**_" #func "**\"\n" \
		".section __TEXT,__objc_methtype,cstring_literals\n"\
		"l_cls_method_type_" #func "_: .asciz \"" #type "\"\n"\
		".section __TEXT,__objc_methname,cstring_literals\n" \
		"l_cls_method_name_" #func "_: .asciz \"" #selector "\"\n"\
		".section __TEXT,__text,regular,pure_instructions\n" \
		"\"cobjc**_" #func "**\": \n" \
		"ldr x15,[x0]\n" \
		"add x15,x15,#0x1c\n" \
		"and x15,x15,#4\n" \
		"cbnz x15,Lcobjc_" #func "_j\n"\
		"adrp x1,_OBJC_IVAR_$_" #class ".cobjc_struct@PAGE\n" \
		"ldrsw x1,[x1,_OBJC_IVAR_$_" #class ".cobjc_struct@PAGEOFF]\n" \
		"Lcobjc_" #func "_j:\n" \
		"b _" #func "\n" \
		".section __DATA,__objc_const\n")
#define ADD_METHOD(class,func,selector) ADD_METHOD_WITH_TYPE(class,func,selector,@@:)
#define _DEFINE_INSTANCE_METHODS(class, count) \
	asm(".section __DATA,__objc_const\n" \
		".p2align 3\n_instance_methods." #class ".objc:\n.long 24\n" \
		".long " count "\n")
#define DEFINE_INSTANCE_METHODS(class,count) _DEFINE_INSTANCE_METHODS(class,#count)

// To be called inside a function
#define COBJC_STRUCT(class,obj) \
	({void *val;asm("adrp x9,_OBJC_IVAR_$_" #class ".cobjc_struct@PAGE\n" \
		"ldrsw x9,[x9,_OBJC_IVAR_$_" #class ".cobjc_struct@PAGEOFF]\n" \
		"add %0,%1,x9":"=r"(val):"r"(obj):"x9");val;})

extern void objc_msgSendSuper2(void);

#define osupercall_t(ret_type,class,obj,...) \
	({uint64_t superclass;asm("adrp %0,l_suprefs_" #class "@PAGE\n" \
		"ldr %0,[%0,l_suprefs_" #class "@PAGEOFF]":"=r"(superclass));\
		uint64_t refs[2]={(uint64_t)obj,(uint64_t)superclass}; \
		_ocall_t(ret_type,objc_msgSendSuper2,(id)&refs,__VA_ARGS__,);})

#define osupercall(class,obj,...) osupercall_t(void*,class,obj,__VA_ARGS__)

#define _COUNT_NUM_ARGS(cnt,first,second,...) \
	IF_ELSE(HAS_ARGS(first))( \
		DEFER2(_COUNT_NUM_ARGS_)()(cnt+1,__VA_ARGS__,,), \
		#cnt \
	)
#define _COUNT_NUM_ARGS_() _COUNT_NUM_ARGS
#define _AFTER_SECOND(a,b,...) __VA_ARGS__
#define _AFTER_FIRST(a,...) __VA_ARGS__
#define ADD_METHOD_CONSUME_3(class,...) \
	IF(HAS_ARGS(FIRST(__VA_ARGS__))) (\
		ADD_METHOD(class,FIRST(__VA_ARGS__),SECOND(__VA_ARGS__)); \
		DEFER2(ADD_METHOD_CONSUME_3_)()(class,_AFTER_SECOND(__VA_ARGS__)) \
	)
#define ADD_METHOD_CONSUME_3_() ADD_METHOD_CONSUME_3
#define ADD_METHOD_CONSUME_1_() ADD_METHOD_CONSUME_1
#define ADD_METHOD_CONSUME_2(class,...) \
	_DEFINE_INSTANCE_METHODS(class,_COUNT_NUM_ARGS(0,__VA_ARGS__,)); \
	ADD_METHOD_CONSUME_3(class,__VA_ARGS__)
#define ADD_METHOD_CONSUME_1(class,...) \
	IF_ELSE(HAS_ARGS(FIRST(__VA_ARGS__))) (\
		ADD_METHOD(class,FIRST(__VA_ARGS__),SECOND(__VA_ARGS__)); \
		DEFER2(ADD_METHOD_CONSUME_1_)()(class,_AFTER_SECOND(__VA_ARGS__)), \
		ADD_METHOD_CONSUME_2(class,_AFTER_FIRST(__VA_ARGS__)) \
	)
#define ADD_METHOD_CONSUME_1_() ADD_METHOD_CONSUME_1
#define MAKE_CLASS(name,base,ivarsize,...) \
	DEFINE_CLASS(name,base,ivarsize); \
	_DEFINE_CLASS_METHODS(name,EVAL(_COUNT_NUM_ARGS(0,__VA_ARGS__,))); \
	EVAL(ADD_METHOD_CONSUME_1(name,__VA_ARGS__))

#pragma once

// protect_method
// @LNSSPsd, May/23/25

#define DISABLE_PROTECT 1

#ifndef DISABLE_PROTECT

#define protect_method(c,s,f) \
	asm("mov x2,%0 \n" \
		"adrp x3,\"!$$protect_method::" #c "::" #s "::dovl\"@PAGE \n" \
		"str x2,[x3,\"!$$protect_method::" #c "::" #s "::dovl\"@PAGEOFF] \n"\
		"adrp x2,\"!$$protect_method::" #c "::" #s "::eval*\"@PAGE \n"\
		"add x2,x2,\"!$$protect_method::" #c "::" #s "::eval*\"@PAGEOFF \n"\
		"adrp x1,\"!sel::" #s "\"@PAGE \n" \
		"ldr x1,[x1,\"!sel::" #s "\"@PAGEOFF] \n"\
		"adrp x0,_OBJC_CLASS_$_" #c "@GOTPAGE\n " \
		"ldr x0,[x0,_OBJC_CLASS_$_" #c "@GOTPAGEOFF]\n " \
		"bl __protect_method_internal\n" \
		"adrp x1,\"!$$protect_method::" #c "::" #s "::dorg\"@PAGE \n" \
		"str x0,[x1,\"!$$protect_method::" #c "::" #s "::dorg\"@PAGEOFF]"\
		:: "r" (f):"x0","x1","x2","x3","x4","x5","x6","x7","x8","x9","x10","x11","x12","x13","x14","x15","x16");\
	asm("b \"L!$$protect_method::" #c "::" #s "::cc\" \n" \
		".section __TEXT,__objc_methname,cstring_literals \n" \
		"\"!meth::" #s "\": \n" \
		".asciz \"" #s "\" \n" \
		".section __DATA,__objc_selrefs,literal_pointers,no_dead_strip \n" \
		"\"!sel::" #s "\":.quad \"!meth::" #s "\" \n" \
		".section __DATA,__common \n" \
		"\"!$$protect_method::" #c "::" #s "::dorg\": .quad 0 \n" \
		"\"!$$protect_method::" #c "::" #s "::dovl\": .quad 0 \n" \
		".section __TEXT,__text,regular,pure_instructions \n" \
		"\"!$$protect_method::" #c "::" #s "::eval*\": \n" \
		"adrp x16,\"#ava%sl1\"@PAGE \n" \
		"add x16,x16,\"#ava%sl1\"@PAGEOFF \n" \
		"ldp x16,x15,[x16] \n" \
		"sub x16,x30,x16 \n" \
		"cmp x16,x15\nb.gt \"L!$$protect_method::" #c "::" #s "::eval*F\" \n" \
		"adrp x16,\"!$$protect_method::" #c "::" #s "::dorg\"@PAGE \n" \
		"ldr x16,[x16,\"!$$protect_method::" #c "::" #s "::dorg\"@PAGEOFF] \n" \
		"br x16\n\"L!$$protect_method::" #c "::" #s "::eval*F\": \n" \
		"adrp x16,\"!$$protect_method::" #c "::" #s "::dovl\"@PAGE \n"\
		"ldr x16,[x16,\"!$$protect_method::" #c "::" #s "::dovl\"@PAGEOFF] \n"\
		"cbz x16,\"L!$$protect_method::" #c "::" #s "::eval*Fr\" \n" \
		"br x16\n\"L!$$protect_method::" #c "::" #s "::eval*Fr\": ret \n" \
		"\"L!$$protect_method::" #c "::" #s "::cc\":")

#else

#define protect_method(...)

#endif

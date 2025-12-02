.section __TEXT,__text,regular,pure_instructions
.globl _battman_bootstrap,_ios_app_exit,____isOSVersionAtLeast
.p2align 2

; current version only works for arm64 iOS :(
; Licensing code and some utilities

#define USE_UIWEBVIEW 1

#ifdef DEBUG
#if USE_UIWEBVIEW
#warning Using UIWebView
#else
#warning Using WKWebView
#endif
#endif

; x0: license_hash
; TODO: hardcode license_hash
_battman_bootstrap:
	sub sp,sp,#64
	cbz w1,L.battman.bootstrap.e
	sub sp,sp,#32 ;16
	cmp w1,#1
	b.eq L.battman.bootstrap.checkdone
	stp x29,x30,[sp]
	bl checktoken
L.battman.bootstrap.checkdone:
	stp x29,x30,[sp,#64]
	stp x19,x20,[sp,#32]
	mov x19,x0
	mov x20,x2
	mov x0,x2
	bl _object_getClass
	mov x2,x0
	adrp x0,_OBJC_CLASS_$_UIWindow@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIWindow@GOTPAGEOFF]
	adrp x3,_OBJC_CLASS_$_UIApplication@GOTPAGE
	ldr x3,[x3,_OBJC_CLASS_$_UIApplication@GOTPAGEOFF]
	cmp x2,x3
	b.ne L.battman.bootstrap.checkdone.1
	adrp x1,sel.1new@PAGE
	ldr x1,[x1,sel.1new@PAGEOFF]
	b L.battman.bootstrap.checkdone.2
L.battman.bootstrap.checkdone.1:
	adrp x1,allocSel@PAGE
	ldr x1,[x1,allocSel@PAGEOFF]
	bl _objc_msgSend
	adrp x1,initWithWS@PAGE
	ldr x1,[x1,initWithWS@PAGEOFF]
	mov x2,x20
L.battman.bootstrap.checkdone.2:
	bl _objc_msgSend
	;mov x2,x0
	;adrp x1,sel.setWindow@PAGE
	;ldr x1,[x1,sel.setWindow@PAGEOFF]
	;mov x0,x19
	mov x19,x0
	adrp x3,_gWindow@PAGE
	str x0,[x3,_gWindow@PAGEOFF]
	;bl _objc_msgSend
	adrp x1,sel.1new@PAGE
	ldr x1,[x1,sel.1new@PAGEOFF]
	adrp x0,_OBJC_CLASS_$_UITabBarController@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UITabBarController@GOTPAGEOFF]
	bl _objc_msgSend
	str x0,[sp,#24]
	adrp x0,_OBJC_CLASS_$_BatteryInfoViewController@PAGE
	add x0,x0,_OBJC_CLASS_$_BatteryInfoViewController@PAGEOFF
	mov x1,sp
	bl .createNC
#ifdef DEBUG
#warning remember to finalize this block when releasing AnalyticsViewController
	adrp x0,_OBJC_CLASS_$_AnalyticsViewController@PAGE
	add x0,x0,_OBJC_CLASS_$_AnalyticsViewController@PAGEOFF
	add x1,sp,#8
	bl .createNC
	adrp x0,_OBJC_CLASS_$_SettingsViewController@PAGE
	add x0,x0,_OBJC_CLASS_$_SettingsViewController@PAGEOFF
	add x1,sp,#16
	bl .createNC
#else
	adrp x0,_OBJC_CLASS_$_SettingsViewController@PAGE
	add x0,x0,_OBJC_CLASS_$_SettingsViewController@PAGEOFF
	add x1,sp,#8
	bl .createNC
#endif
	;adrp x0,_OBJC_CLASS_$_NSArray@GOTPAGE
	;ldr x0,[x0,_OBJC_CLASS_$_NSArray@GOTPAGEOFF]
	;adrp x1,.sel.arrwobjs@PAGE
	;ldr x1,[x1,.sel.arrwobjs@PAGEOFF]
	bl show_license
	cbz x0,.createNC
	mov x0,x19
	mov x2,sp
#ifdef DEBUG
#warning remember to finalize this block when releasing AnalyticsViewController
	mov x3,#3
#else
	mov x3,#2
#endif
	bl _objc_msgSend
	adrp x1,.sel.setRootVCs@PAGE
	ldr x1,[x1,.sel.setRootVCs@PAGEOFF]
	mov x2,x0
	mov x3,#0
	ldr x0,[sp,#24]
	bl _objc_msgSend
	ldr x2,[sp,#24]
	adrp x1,s.setRootVC@PAGE
	ldr x1,[x1,s.setRootVC@PAGEOFF]
	mov x0,x19
	bl _objc_msgSend
	adrp x1,sel.makeKeyAndVisible@PAGE
	ldr x1,[x1,sel.makeKeyAndVisible@PAGEOFF]
	mov x0,x19
	bl _objc_msgSend
	ldp x29,x30,[sp,#64]
	ldp x19,x20,[sp,#32]
	add sp,sp,#80
	ret
L.battman.bootstrap.e:
	stp x29,x30,[sp,#48]
	stp x19,x20,[sp,#32]
	;mov x20,x0
	;adrp x0,uiresponderclass@PAGE
	;add x0,x0,uiresponderclass@PAGEOFF
	;bl _objc_getRequiredClass
	;mov x20,x0
	mov x1,#512
	str x1,[sp]
	mov x0,#512
	bl _malloc
	mov x19,x0
	mov x1,sp
	bl __NSGetExecutablePath
	mov x0,x19
	bl _strlen
	add x1,x19,x0
L.battman.bootstrap.el:
	sub x1,x1,#1
	ldrb w2,[x1]
	cmp w2,#0x2f
	b.ne L.battman.bootstrap.el
	mov w0,#0
	strb w0,[x1,#13]
	movz x0,#0x696c
	movk x0,#0x736e,LSL #32
	cbz x19,L.battman.bootstrap.cont
	movk x0,#0x2e65,LSL #48
	movk x0,#0x6563,LSL #16
	str x0,[x1,#1]
	movz w0,#0x7468
	movk w0,#0x6c6d,LSL #16
	str w0,[x1,#9]
	;cmp x19,#0
	;b.eq L.battman.bootstrap.cont
	mov x16,#5
	mov x2,#0
	mov x1,#0
	mov x0,x19
	svc #0x80
	b.cc L.battman.bootstrap.c1
	mov x29,x16
	svc #0x80
	b L.battman.bootstrap.cont
L.battman.bootstrap.c1:
	str x0,[sp]
	mov x1,x19
	mov x16,#189
	svc #0x80
	b.cs L.battman.bootstrap.cont
	ldr x1,[x19,#72]
	adrp x9,.lfd.s@PAGE
	str x1,[x9,.lfd.s@PAGEOFF]
	mov x0,#0
	mov x2,#1
	mov x3,#0
	ldr x4,[sp]
	mov x5,xzr
	mov x16,#197
	svc #0x80
	b.cs L.battman.bootstrap.cont
	mov x16,x19
	mov x19,x0
	mov x0,x16
	bl _free
	adrp x0,.lfd.1@PAGE
	str x19,[x0,.lfd.1@PAGEOFF]
	ldr x16,[sp]
	mov x0,x16
	mov x16,#6
	svc #0x80
	;adrp x9,.lfd.0@PAGE
	;str x16,[x9,.lfd.0@PAGEOFF]
	adrp x0,_OBJC_CLASS_$_UIResponder@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIResponder@GOTPAGEOFF]
L.battman.bootstrap.cont:
	adrp x1,sel.class@PAGE
	ldr x1,[x1,sel.class@PAGEOFF]
	bl _objc_msgSend
	adrp x1,sceneName@PAGE
	add x1,x1,sceneName@PAGEOFF
	mov x2,#0
	bl _objc_allocateClassPair
	adrp x10,TStr@PAGE
	add x10,x10,TStr@PAGEOFF
	str x10,[sp]
	adrp x1,UIWindowType@PAGE
	add x1,x1,UIWindowType@PAGEOFF
	str x1,[sp,#8]
	add x10,x10,#1
	str x10,[sp,#24]
	adrp x1,C_CStr@PAGE
	add x1,x1,C_CStr@PAGEOFF
	str x1,[sp,#16]
	adrp x1,m.window@PAGE
	add x1,x1,m.window@PAGEOFF
	mov x2,sp
	mov x3,#2
	mov x19,x0
	bl _class_addProperty
	mov x0,x19
	adrp x1,sel.window@PAGE
	ldr x1,[x1,sel.window@PAGEOFF]
	adrp x2,noParamSign@PAGE
	add x3,x2,noParamSign@PAGEOFF
	adrp x2,.gWindow.get@PAGE
	add x2,x2,.gWindow.get@PAGEOFF
	bl _class_addMethod
	mov x0,x19
	adrp x1,s..sceneInit@PAGE
	ldr x1,[x1,s..sceneInit@PAGEOFF]
	adrp x2,sceneInitSign@PAGE
	add x3,x2,sceneInitSign@PAGEOFF
	adrp x2,_battman_bootstrap@PAGE
	add x2,x2,_battman_bootstrap@PAGEOFF
	bl _class_addMethod
	adrp x0,UISceneDelegate_str@PAGE
	add x0,x0,UISceneDelegate_str@PAGEOFF
	bl _objc_getProtocol
	mov x1,x0
	mov x0,x19
	bl _class_addProtocol
	mov x0,x19
	bl _objc_registerClassPair
	adrp x0,_OBJC_CLASS_$_UIResponder@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIResponder@GOTPAGEOFF]
	adrp x1,sel.class@PAGE
	ldr x1,[x1,sel.class@PAGEOFF]
	bl _objc_msgSend
	adrp x1,meth.makeKeyAndVisible@PAGE
	add x1,x1,meth.makeKeyAndVisible@PAGEOFF
	mov x2,xzr
	bl _objc_allocateClassPair
	mov x19,x0
	adrp x20,.returnTrue@PAGE
	add x20,x20,.returnTrue@PAGEOFF
	adrp x0,_OBJC_CLASS_$_NSProcessInfo@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_NSProcessInfo@GOTPAGEOFF]
	adrp x1,sel.processInfo@PAGE
	ldr x1,[x1,sel.processInfo@PAGEOFF]
	bl _objc_msgSend
	adrp x1,sel.iOSAtLeast@PAGE
	ldr x1,[x1,sel.iOSAtLeast@PAGEOFF]
	adrp x2,iOS13ver@PAGE
	add x2,x2,iOS13ver@PAGEOFF
	bl _objc_msgSend
	adrp x2,_battman_bootstrap@PAGE
	add x2,x2,_battman_bootstrap@PAGEOFF
	tbz x0,#0,L.battman.bootstrap.cont.1 ;b.eq!!!
	adrp x10,.osSupportsUIScene@PAGE
	str x0,[x10,.osSupportsUIScene@PAGEOFF]
	mov x2,x20
L.battman.bootstrap.cont.1:
	adrp x1,finishLaunching_sel@PAGE
	ldr x1,[x1,finishLaunching_sel@PAGEOFF]
	adrp x3,appFinSign@PAGE
	add x3,x3,appFinSign@PAGEOFF
	mov x0,x19
	bl _class_addMethod
	mov x0,x19
	adrp x1,sel.confScene@PAGE
	ldr x1,[x1,sel.confScene@PAGEOFF]
	adrp x2,.confScene@PAGE
	add x2,x2,.confScene@PAGEOFF
	adrp x3,sceneConfSign@PAGE
	add x3,x3,sceneConfSign@PAGEOFF
	;bl _class_addMethod
	mov x0,x19
	bl _objc_registerClassPair
	mov x0,x19
	bl _NSStringFromClass
	ldp x19,x20,[sp,#32]
	ldp x29,x30,[sp,#48]
	add sp,sp,#64
	ret
.confScene:
	sub sp,sp,#32
	stp x29,x30,[sp,#16]
	stp x22,x23,[sp]
	mov x0,x3
	adrp x1,sel.role@PAGE
	ldr x1,[x1,sel.role@PAGEOFF]
	bl _objc_msgSend
	mov x22,x0
	adrp x0,defaultConfigurationStr@PAGE
	add x0,x0,defaultConfigurationStr@PAGEOFF
	bl ___CFStringMakeConstantString
	mov x23,x0
	adrp x0,UISceneConfiguration_str@PAGE
	add x0,x0,UISceneConfiguration_str@PAGEOFF
	bl _objc_getRequiredClass
	adrp x1,allocSel@PAGE
	ldr x1,[x1,allocSel@PAGEOFF]
	bl _objc_msgSend
	mov x3,x22
	mov x2,x23
	adrp x1,sel.initWithNameEtSessionRole@PAGE
	ldr x1,[x1,sel.initWithNameEtSessionRole@PAGEOFF]
	bl _objc_msgSend
	ldp x22,x23,[sp]
	ldp x29,x30,[sp,#16]
	add sp,sp,#32
	ret

.returnTrue:
	mov x0,#1
	ret

.gWindow.get:
	adrp x0,_gWindow@PAGE
	ldr x0,[x0,_gWindow@PAGEOFF]
	ret

checktoken:
	;sub x30,x30,#32
	;str x30,[sp,#64]
	ldp x29,x30,[sp]
	stp x29,x30,[sp,#80]
	str x2,[sp,#72]
	adrp x9,.lfd.1@PAGE
	ldr x0,[x9,.lfd.1@PAGEOFF]
	adrp x1,.lfd.s@PAGE
	ldr x1,[x1,.lfd.s@PAGEOFF]
	mov x2,sp
	bl _CC_SHA256
	b Lchecktoken.pt
	add x2,sp,#16
	;adrp x1,.licensing.S.end@PAGE
	;add x1,x1,.licensing.S.end@PAGEOFF
	ldr x0,[sp,#64]
	sub x1,x1,x0
	str x1,[sp,#32]
	mov x0,x1
	bl _malloc
	str x0,[sp,#40]
	ldr x1,[sp,#64]
	ldr x2,[sp,#32]
	bl _memcpy
	ldr x9,[sp,#40]
	ldr x10,[sp,#32]
	add x10,x9,x10
	movz w1,#0x9000,LSL #16
Lchecktoken.ll:
	ldr w11,[x9]
	and w11,w11,w1
	cmp w11,w1
	b.ne Lchecktoken.llna
	str wzr,[x9]
Lchecktoken.llna:
	add x9,x9,#4
	cmp x9,x10
	b.ne Lchecktoken.ll
	add x2,sp,#16
	ldr x0,[sp,#40]
	ldr x1,[sp,#32]
	bl _CC_SHA256
Lchecktoken.pt:
	adrp x0,_lh_arr@PAGE
	add x0,x0,_lh_arr@PAGEOFF
	mov x16,sp
	ldp q0,q2,[x16]
	ldp q1,q3,[x0]
	cmeq v0.2d,v1.2d,v0.2d
	cmeq v1.2d,v2.2d,v3.2d
	uminp v0.16b,v1.16b,v0.16b
	uminv b0,v0.16b
	umov w0,v0.b[0]
	ldr x9,[sp,#80]
	tbnz w0,#0,Lchecktoken.b
	add x3,sp,#32
	mov x0,x16
Lchecktoken.a:
	cmp x3,x16
	b.eq Lchecktoken.b
	ldr x1,[x16]
	ldr x2,[x0]
	cmp x1,x2
	add x16,x16,#8
	add x0,x0,#8
	b.eq Lchecktoken.a
	mov x9,x1
Lchecktoken.b:
	str x9,[sp,#80]
	ldp x29,x30,[sp,#80]
	ldr x2,[sp,#72]
	add sp,sp,#112
	mov x1,#1
	b _battman_bootstrap

; x0: victim
; x1: sel
; x2: src
; x3: nop (0)
;     use safeAreaLayoutGuide ? (1)
;     src different selector
bindAnchors:
	sub sp,sp,#32
	stp x22,x23,[sp]
	stp x29,x30,[sp,#16]
	mov x22,x0
	mov x23,x1
	cmp x3,#1
	mov x0,x2
	b.ne LbindAnchors.nosafearea
	adrp x1,sel.salg@PAGE
	ldr x1,[x1,sel.salg@PAGEOFF]
	bl _objc_msgSend
	mov x1,x23
	b LbindAnchors.continue
LbindAnchors.nosafearea:
	mov x1,x23
	cbz x3,LbindAnchors.continue
	mov x1,x3
LbindAnchors.continue:
	bl _objc_msgSend
	mov x1,x23
	mov x23,x0
	mov x0,x22
	bl _objc_msgSend
	adrp x1,sel.ceta@PAGE
	ldr x1,[x1,sel.ceta@PAGEOFF]
	mov x2,x23
	bl _objc_msgSend
	adrp x1,sel.setActive@PAGE
	ldr x1,[x1,sel.setActive@PAGEOFF]
	mov x2,#1
	bl _objc_msgSend
	ldp x22,x23,[sp]
	ldp x29,x30,[sp,#16]
	add sp,sp,#32
	ret

; Block: https://clang.llvm.org/docs/Block-ABI-Apple.html
; x0: title (must be constant)
; x1: action addr.
; x2: addt. ptr
makeBarButtonItem:
	sub sp,sp,#64
	str x24,[sp,#40]
	stp x29,x30,[sp,#48]
	str x1,[sp,#16]
	str x2,[sp,#32]
#if 0
	bl ___CFStringMakeConstantString
	mov x24,x0
#else
    mov x1, x0
    mov x0, xzr
    movz x2, #0x0100
    movk x2, #0x0800, lsl #16 ; kCFStringEncodingUTF8
    bl _CFStringCreateWithCString
    mov x24, x0
#endif
	adrp x0,__NSConcreteStackBlock@GOTPAGE
	ldr x0,[x0,__NSConcreteStackBlock@GOTPAGEOFF]
	mov x1,#0x60000000
	stp x0,x1,[sp]
	adrp x0,"1ImpBlockDescriptor"@PAGE
	add x0,x0,"1ImpBlockDescriptor"@PAGEOFF
	str x0,[sp,#24]
	mov x0,sp
	adrp x1,sel.copy@PAGE
	ldr x1,[x1,sel.copy@PAGEOFF]
	bl _objc_msgSend
	str x0,[sp]
	adrp x1,allocSel@PAGE
	ldr x1,[x1,allocSel@PAGEOFF]
	adrp x0,_OBJC_CLASS_$_UIBarButtonItem@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIBarButtonItem@GOTPAGEOFF]
	bl _objc_msgSend
	mov x2,x24
	mov x3,#0
	ldr x4,[sp]
	adrp x5,sel.invoke@PAGE
	ldr x5,[x5,sel.invoke@PAGEOFF]
	adrp x1,sel.initWithTSTA@PAGE
	ldr x1,[x1,sel.initWithTSTA@PAGEOFF]
	bl _objc_msgSend
	ldr x24,[sp,#40]
	ldp x29,x30,[sp,#48]
	add sp,sp,#64
	ret

show_license.a:
	sub sp,sp,#48
	stp x29,x30,[sp,#32]
	stp x19,x20,[sp,#16]
	;ldr x0,[x0,#32]
	adrp x0,_OBJC_CLASS_$_UIApplication@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIApplication@GOTPAGEOFF]
	adrp x1,sel.sharedApp@PAGE
	ldr x1,[x1,sel.sharedApp@PAGEOFF]
	bl _objc_msgSend
	str x0,[sp,#8]
	str xzr,[sp]
	bl show_license
show_license.susp:
	sub sp,sp,#32
	stp x29,x30,[sp]
	adrp x0,_OBJC_CLASS_$_UIApplication@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIApplication@GOTPAGEOFF]
	adrp x1,sel.sharedApp@PAGE
	ldr x1,[x1,sel.sharedApp@PAGEOFF]
	bl _objc_msgSend
	adrp x1,sel.suspend@PAGE
	ldr x1,[x1,sel.suspend@PAGEOFF]
	bl _objc_msgSend
	ldp x29,x30,[sp]
	add sp,sp,#32
	ret
show_license.cb.dbg:
	; tmp dbg
	ldr x9,[sp,#96]
	cbnz x9,show_license.cb
	adrp x9,_THENUM@PAGE
	str x0,[x9,_THENUM@PAGEOFF]
	add sp,sp,#96
	ldp x29,x30,[sp,#16]
	add sp,sp,#32
	ret
show_license.cb:
	ldr x0,[sp,#32]
	bl _free
show_license.pcb:
	adrp x0,_OBJC_CLASS_$_UIViewController@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIViewController@GOTPAGEOFF]
	add x1,sp,xzr
	bl .createNC
	mov x20,x0
	adrp x1,sel.navItem@PAGE
	ldr x1,[x1,sel.navItem@PAGEOFF]
	bl _objc_msgSend
	;adrp x1,sel.topItem@PAGE
	;ldr x1,[x1,sel.topItem@PAGEOFF]
	;bl _objc_msgSend
	str x21,[sp,#16]
	mov x21,x0
	adrp x0,licenseStr@PAGE
	add x0,x0,licenseStr@PAGEOFF
	bl _cond_localize
	mov x2,x0
	mov x0,x21
	adrp x1,sel.setTitle@PAGE
	ldr x1,[x1,sel.setTitle@PAGEOFF]
	bl _objc_msgSend
	mov x0,x20
	adrp x1,sel.loadView@PAGE
	ldr x1,[x1,sel.loadView@PAGEOFF]
	bl _objc_msgSend
	mov x0,x20
	adrp x1,sel.view@PAGE
	ldr x1,[x1,sel.view@PAGEOFF]
	bl _objc_msgSend
	mov x20,x0
	sub sp,sp,#32 ; ATTN sp
	adrp x0,agreeStr@PAGE
	add x0,x0,agreeStr@PAGEOFF
#ifdef USE_GETTEXT
    bl _cond_localize_c
#endif
	mov x2,#0
	adrp x1,show_license.a@PAGE
	add x1,x1,show_license.a@PAGEOFF
	bl makeBarButtonItem
	mov x21,x0
	adrp x0,declineStr@PAGE
	add x0,x0,declineStr@PAGEOFF
#ifdef USE_GETTEXT
    bl _cond_localize_c
#endif
	adrp x1,show_license.susp@PAGE
	add x1,x1,show_license.susp@PAGEOFF
	mov x2,x19
	bl makeBarButtonItem
	str x0,[sp,#16]
	adrp x0,_OBJC_CLASS_$_UIBarButtonItem@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIBarButtonItem@GOTPAGEOFF]
	adrp x1,allocSel@PAGE
	ldr x1,[x1,allocSel@PAGEOFF]
	bl _objc_msgSend
	adrp x1,sel.initWithBBSI@PAGE
	ldr x1,[x1,sel.initWithBBSI@PAGEOFF]
	mov x3,xzr
	mov x4,xzr
	mov x2,#5
	bl _objc_msgSend
	stp x21,x0,[sp]
	adrp x0,_OBJC_CLASS_$_NSArray@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_NSArray@GOTPAGEOFF]
	adrp x1,.sel.arrwobjs@PAGE
	ldr x1,[x1,.sel.arrwobjs@PAGEOFF]
	mov x2,sp
	mov x3,#3
	bl _objc_msgSend
	add sp,sp,#32
	str x0,[sp,#8]
	; Create WebView with proper frame and configuration
	mov x0,x20

#ifdef USE_UIWEBVIEW
	adrp x0,_OBJC_CLASS_$_UIWebView@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIWebView@GOTPAGEOFF]
	adrp x1,sel.1new@PAGE
	ldr x1,[x1,sel.1new@PAGEOFF]
	bl _objc_msgSend
	mov x21,x0
	mov x0,x21
	adrp x1,sel.setOpaque@PAGE
	ldr x1,[x1,sel.setOpaque@PAGEOFF]
	mov x2,#1
	bl _objc_msgSend
	adrp x0,_OBJC_CLASS_$_UIColor@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIColor@GOTPAGEOFF]
	adrp x1,sel.respondsToSelector@PAGE
	ldr x1,[x1,sel.respondsToSelector@PAGEOFF]
	adrp x2,sel.systemBackgroundColor@PAGE
	ldr x2,[x2,sel.systemBackgroundColor@PAGEOFF]
	bl _objc_msgSend
	cbz x0,wv_b_w
	adrp x0,_OBJC_CLASS_$_UIColor@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIColor@GOTPAGEOFF]
	adrp x1,sel.systemBackgroundColor@PAGE
	ldr x1,[x1,sel.systemBackgroundColor@PAGEOFF]
	bl _objc_msgSend
	cbz x0,wv_b_w
	b wv_b
wv_b_w:
	adrp x0,_OBJC_CLASS_$_UIColor@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIColor@GOTPAGEOFF]
	adrp x1,sel.whiteColor@PAGE
	ldr x1,[x1,sel.whiteColor@PAGEOFF]
	bl _objc_msgSend
	cbz x0,wv_done
wv_b:
	mov x2,x0
	mov x0,x21
	adrp x1,sel.setBackgroundColor@PAGE
	ldr x1,[x1,sel.setBackgroundColor@PAGEOFF]
	bl _objc_msgSend
#else
	sub sp,sp,#32
	adrp x0,_OBJC_CLASS_$_WKWebViewConfiguration@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_WKWebViewConfiguration@GOTPAGEOFF]
	adrp x1,sel.1new@PAGE
	ldr x1,[x1,sel.1new@PAGEOFF]
	bl _objc_msgSend
	cbz x0,wv_simple
	str x0,[sp]
	adrp x0,_OBJC_CLASS_$_WKUserScript@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_WKUserScript@GOTPAGEOFF]
	adrp x1,allocSel@PAGE
	ldr x1,[x1,allocSel@PAGEOFF]
	bl _objc_msgSend
	str x0,[sp,#8]
	adrp x0,js_disable_sharedworker@PAGE
	add x0,x0,js_disable_sharedworker@PAGEOFF
	bl ___CFStringMakeConstantString
	str x0,[sp,#16]
	ldr x0,[sp,#8]
	adrp x1,sel.initWithSourceInjectionTime@PAGE
	ldr x1,[x1,sel.initWithSourceInjectionTime@PAGEOFF]
	ldr x2,[sp,#16]
	mov x3,xzr
	mov x4,xzr
	bl _objc_msgSend
	str x0,[sp,#8]
	; Get userContentController from configuration
	ldr x0,[sp]
	adrp x1,sel.userContentController@PAGE
	ldr x1,[x1,sel.userContentController@PAGEOFF]
	bl _objc_msgSend
	str x0,[sp,#24]
	ldr x0,[sp,#24]
	adrp x1,sel.addUserScript@PAGE
	ldr x1,[x1,sel.addUserScript@PAGEOFF]
	ldr x2,[sp,#8]
	bl _objc_msgSend
	adrp x0,_OBJC_CLASS_$_WKWebView@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_WKWebView@GOTPAGEOFF]
	adrp x1,allocSel@PAGE
	ldr x1,[x1,allocSel@PAGEOFF]
	bl _objc_msgSend
	str x0,[sp,#8]
	mov x0,x20
	adrp x1,sel.bounds@PAGE
	ldr x1,[x1,sel.bounds@PAGEOFF]
	bl _objc_msgSend
	cbz x0,wv_simple
	adrp x1,sel.initWithFrameConfiguration@PAGE
	ldr x1,[x1,sel.initWithFrameConfiguration@PAGEOFF]
	ldr x2,[sp]
	bl _objc_msgSend
	cbz x0,wv_simple
	add sp,sp,#32
	mov x21,x0
	b wv_done
#endif

wv_simple:
#ifndef USE_UIWEBVIEW
	adrp x0,_OBJC_CLASS_$_WKWebView@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_WKWebView@GOTPAGEOFF]
	adrp x1,allocSel@PAGE
	ldr x1,[x1,allocSel@PAGEOFF]
	bl _objc_msgSend
	str x0,[sp]
	; ~~Frame data is already in d0-d3~~
	; bruh no way they are still there
	mov x0,x20
	adrp x1,sel.bounds@PAGE
	ldr x1,[x1,sel.bounds@PAGEOFF]
	bl _objc_msgSend
	ldr x0,[sp]
	adrp x1,sel.initWithFrame@PAGE
	ldr x1,[x1,sel.initWithFrame@PAGEOFF]
	bl _objc_msgSend
	add sp,sp,#32
	mov x21,x0
#endif

wv_done:
	mov x0,x20
	mov x2,x21
	adrp x1,sel.addSubview@PAGE
	ldr x1,[x1,sel.addSubview@PAGEOFF]
	bl _objc_msgSend
	mov x0,x21
	mov x2,xzr
	adrp x1,sel.tamic@PAGE
	ldr x1,[x1,sel.tamic@PAGEOFF]
	bl _objc_msgSend
	mov x2,x20
	mov x0,x21
	mov x3,#0
	adrp x1,sel.topAnchor@PAGE
	ldr x1,[x1,sel.topAnchor@PAGEOFF]
	bl bindAnchors
	mov x0,x21
	mov x2,x20
	mov x3,#0
	adrp x1,sel.leadingAnchor@PAGE
	ldr x1,[x1,sel.leadingAnchor@PAGEOFF]
	bl bindAnchors
	mov x0,x21
	mov x2,x20
	mov x3,#0
	adrp x1,sel.trailingAnchor@PAGE
	ldr x1,[x1,sel.trailingAnchor@PAGEOFF]
	bl bindAnchors
	mov x0,x21
	mov x3,xzr
	adrp x1,sel.bottomAnchor@PAGE
	ldr x1,[x1,sel.bottomAnchor@PAGEOFF]
	mov x2,x20
	bl bindAnchors
	mov x20,x21
	adrp x0,_OBJC_CLASS_$_UIToolbar@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIToolbar@GOTPAGEOFF]
	adrp x1,sel.1new@PAGE
	ldr x1,[x1,sel.1new@PAGEOFF]
	bl _objc_msgSend
	mov x21,x0
	adrp x1,sel.tamic@PAGE
	ldr x1,[x1,sel.tamic@PAGEOFF]
	mov x2,xzr
	bl _objc_msgSend
	mov x0,x21
	adrp x1,sel.setItems@PAGE
	ldr x1,[x1,sel.setItems@PAGEOFF]
	ldr x2,[sp,#8]
	bl _objc_msgSend
	mov x2,x21
	mov x0,x20
	adrp x1,sel.addSubview@PAGE
	ldr x1,[x1,sel.addSubview@PAGEOFF]
	bl _objc_msgSend
	mov x0,x21
	mov x2,x20
	adrp x1,sel.leadingAnchor@PAGE
	ldr x1,[x1,sel.leadingAnchor@PAGEOFF]
	mov x3,xzr
	bl bindAnchors
	mov x0,x21
	mov x2,x20
	adrp x1,sel.trailingAnchor@PAGE
	ldr x1,[x1,sel.trailingAnchor@PAGEOFF]
	mov x3,xzr
	bl bindAnchors
	mov x0,x21
	mov x2,x20
	adrp x1,sel.bottomAnchor@PAGE
	ldr x1,[x1,sel.bottomAnchor@PAGEOFF]
	mov x3,#1
	bl bindAnchors
	ldr x21,[sp,#16]
	adrp x3,.lfd.s@PAGE
	ldr x2,[x3,.lfd.s@PAGEOFF]
	adrp x10,.lfd.1@PAGE
	ldr x1,[x10,.lfd.1@PAGEOFF]
	; Check if we have valid content
	cbz x1,load_from_url
	cbz x2,load_from_url
	sub sp,sp,#64
	mov x0,x1
	mov x1,x2
	mov x2,sp
	bl _CC_SHA256
	adrp x0,_lh_arr@PAGE
	add x0,x0,_lh_arr@PAGEOFF
	mov x16,sp
	ldp q0,q2,[x16]
	ldp q1,q3,[x0]
	cmeq v0.2d,v1.2d,v0.2d
	cmeq v1.2d,v2.2d,v3.2d
	uminp v0.16b,v1.16b,v0.16b
	uminv b0,v0.16b
	umov w0,v0.b[0]
	add sp,sp,#64
	cmp w0,#0xFF
	b.eq load_local_html

load_from_url:
	; I've decided to fallback to URL, but this does not seems safe enough
	bl _showCompletionAlert

load_local_html:
	; Load local HTML content
	mov x0,#0
	adrp x3,.lfd.s@PAGE
	ldr x2,[x3,.lfd.s@PAGEOFF]
	adrp x10,.lfd.1@PAGE
	ldr x1,[x10,.lfd.1@PAGEOFF]
	mov x3,#0x100
	movk x3,#0x800,LSL #16
	mov w4,#0
	bl _CFStringCreateWithBytes
	str x0,[sp,#8]
	;adrp x1,.lfd.s@PAGE
	;ldr x1,[x1,.lfd.s@PAGEOFF]
	;adrp x0,.lfd.1@PAGE
	;ldr x0,[x0,.lfd.1@PAGEOFF]
	;mov x16,#73
	;svc #0x80
	;str xzr,[sp,#16]
	mov x1,#47
	str w1,[sp,#16]
	add x1,sp,#16
	mov x0,xzr
	mov x2,#0x100
	movk x2,#0x800,LSL #16
	bl _CFStringCreateWithCString
	mov x1,x0
	mov x0,xzr
	mov x2,x0
	mov x3,#1
	bl _CFURLCreateWithFileSystemPath
	mov x3,x0
	ldr x2,[sp,#8]
	mov x0,x20
#ifdef USE_UIWEBVIEW
	; UIWebView uses loadHTMLString:baseURL: method
	adrp x1,sel.loadHTMLStringBaseURL@PAGE
	ldr x1,[x1,sel.loadHTMLStringBaseURL@PAGEOFF]
#else
	; WKWebView uses loadHTMLString:baseURL: method
	adrp x1,sel.loadHTMLString@PAGE
	ldr x1,[x1,sel.loadHTMLString@PAGEOFF]
#endif
	bl _objc_msgSend
continue_setup:
	mov x0,x19
	ldr x2,[sp]
	adrp x1,s.setRootVC@PAGE
	ldr x1,[x1,s.setRootVC@PAGEOFF]
	bl _objc_msgSend
	mov x0,x19
	adrp x1,sel.makeKeyAndVisible@PAGE
	ldr x1,[x1,sel.makeKeyAndVisible@PAGEOFF]
	bl _objc_msgSend
	add x0,sp,#128
	ldp x19,x20,[sp,#128]
	ldp x29,x30,[x0,#32]
	add sp,sp,#176
	b show_license.return.succ
show_license:
	adrp x0,IOPUUID@PAGE
	add x0,x0,IOPUUID@PAGEOFF
	bl ___CFStringMakeConstantString
	mov x20,x0
	adrp x0,IOPExpDev@PAGE
	add x0,x0,IOPExpDev@PAGEOFF
	bl _IOServiceMatching
	mov x1,x0
	mov x0,xzr
	bl _IOServiceGetMatchingService
	cbz w0,show_license.return.fail
	mov x9,x20
	mov x20,x0
	mov x2,xzr
	mov x3,x2
	mov x1,x9
	bl _IORegistryEntryCreateCFProperty
	cbz w0,show_license.return.fail
	sub sp,sp,#64
	mov x1,#0x0100
	movk x1,#0x0800,LSL #16
	bl _CFStringGetCStringPtr
	mov x1,x0
	mov x0,sp
	mov x2,#32
	bl _memcpy
	adrp x0,_lh_arr@PAGE
	add x1,x0,_lh_arr@PAGEOFF
	mov x2,#32
	add x0,sp,x2
	bl _memcpy
	mov x0,x20
	bl _IOObjectRelease
	mov x0,sp
	mov x1,#64
	sub sp,sp,#32
	;sub x2,x0,sp
	mov x2,sp
	bl _CC_SHA256
	bl _battman_config_dir
	mov x20,x0
	bl _strlen
	cmp x0,#512
	b.gt show_license.1
	mov x0,#512
show_license.1:
	add x0,x0,#7
	bl _malloc
	str x0,[sp,#32]
	mov x1,x20
	bl _stpcpy
	adrp x1,tokenFile@PAGE
	add x1,x1,tokenFile@PAGEOFF
	bl _stpcpy
	ldrb w1,[x0]
	ldr x0,[sp,#32]
	mov x16,#5
	ldr x9,[sp,#96]
	cbnz x9,show_license.1.svc
	mov x1,#0x202
	mov x2,#0x180
show_license.1.svc:
	svc #0x80
	str w0,[sp,#40]
	;ldr x0,[sp,#32]
	;bl _free
	b.cs show_license.cb
	ldr x16,[sp,#96]
	cbnz x16,show_license.2
	mov x20,x0
	ldr x0,[sp,#32]
	bl _free
	mov x0,x20
	mov x1,sp
	mov x2,#32
	mov x16,#4
	svc #0x80
	b.cs show_license.return.fail
	ldr x0,[sp,#32]
	mov x16,#6
	svc #0x80
	add sp,sp,#96
	ldr x20,[sp,#8]
	adrp x1,sel.keyWindow@PAGE
	ldr x1,[x1,sel.keyWindow@PAGEOFF]
	mov x0,x20
	bl _objc_msgSend
	adrp x1,sel.setHidden@PAGE
	ldr x1,[x1,sel.setHidden@PAGEOFF]
	mov x2,#1
	bl _objc_msgSend
	adrp x9,.osSupportsUIScene@PAGE
	ldr x9,[x9,.osSupportsUIScene@PAGEOFF]
	tbz x9,#0,show_license.1.noscene
	mov x0,x20
	adrp x1,sel.connectedScenes@PAGE
	ldr x1,[x1,sel.connectedScenes@PAGEOFF]
	bl _objc_msgSend
	adrp x1,sel.anyObject@PAGE
	ldr x1,[x1,sel.anyObject@PAGEOFF]
	bl _objc_msgSend
	str x0,[sp]
	adrp x1,sel.delegate@PAGE
	ldr x1,[x1,sel.delegate@PAGEOFF]
	bl _objc_msgSend
	ldr x2,[sp]
	b show_license.1.withscene
show_license.1.noscene:
	mov x2,x20
show_license.1.withscene:
	mov x1,#2
	bl _battman_bootstrap
	ldp x29,x30,[sp,#32]
	ldp x19,x20,[sp,#16]
	add sp,sp,#48
	ret
show_license.2:
	mov x16,#189
	;ldr w0,[sp,#40]
	ldr x1,[sp,#32]
	svc #0x80
	b.cs show_license.cb
	ldr x1,[sp,#32]
	ldr x1,[x1,#72]
	str w1,[sp,#44]
	mov x0,#0
	mov x2,#1
	mov x3,xzr
	ldr w4,[sp,#40]
	mov x5,#0
	mov x16,#197
	svc #0x80
	b.cs show_license.return.succ
	mov x20,x0
	ldr x0,[sp,#32]
	bl _free
	ldr w0,[sp,#40]
	mov x16,#6
	svc #0x80
	ldp q0,q1,[sp]
	ldp q2,q3,[x20]
	cmeq v0.2d,v0.2d,v2.2d
	cmeq v1.2d,v1.2d,v3.2d
	uminp v0.16b,v0.16b,v1.16b
	uminv b0,v0.16b
	umov w0,v0.b[0]
	cmp w0,#0xFF
	b.ne show_license.pcb
show_license.3:
	add x2,sp,#96
	str x2,[sp]
	mov x0,x19
	ldr w1,[sp,#44]
	mov x16,#73
	svc #0x80
	ldr x2,[sp]
	adrp x1,.sel.arrwobjs@PAGE
	ldr x1,[x1,.sel.arrwobjs@PAGEOFF]
	adrp x0,_OBJC_CLASS_$_NSArray@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_NSArray@GOTPAGEOFF]
#ifdef DEBUG
#warning remember to finalize this block when releasing AnalyticsViewController
	mov x3,#3
#else
	mov x3,#2
#endif
	bl _objc_msgSend
	mov x2,x0
	adrp x1,.sel.setRootVCs@PAGE
	ldr x1,[x1,.sel.setRootVCs@PAGEOFF]
	ldr x0,[sp,#120]
	mov x20,x0
	bl _objc_msgSend
	mov x2,x20
	adrp x1,s.setRootVC@PAGE
	ldr x1,[x1,s.setRootVC@PAGEOFF]
	mov x0,x19
	bl _objc_msgSend
	mov x0,x19
	adrp x1,sel.makeKeyAndVisible@PAGE
	ldr x1,[x1,sel.makeKeyAndVisible@PAGEOFF]
	bl _objc_msgSend
	add x0,sp,#128
	ldp x19,x20,[x0]
	add sp,sp,#176
	ldp x29,x30,[x0,#32]
	b show_license.return.succ
show_license.return.fail:
	mov x0,#0
	b show_license.return
show_license.return.succ:
	mov x0,#1
show_license.return:
	ret

; x19 to x29 are callee saved

; x0: out (size>=32)
get_token:
	sub sp,sp,#80
	str x0,[sp,#48]
	stp x29,x30,[sp,#64]
	stp x19,x20,[sp]
	;adrp x0,_OBJC_CLASS_$_UIDevice@GOTPAGE
	adrp x0,UIDevice_str@PAGE
	add x0,x0,UIDevice_str@PAGEOFF
	bl _objc_getRequiredClass
	mov x19,x0
	adrp x0,curDevStr@PAGE
	add x0,x0,curDevStr@PAGEOFF
	bl _sel_registerName
	mov x1,x0
	mov x0,x19
	bl _objc_msgSend
	mov x19,x0
	adrp x0,idForVendStr@PAGE
	add x0,x0,idForVendStr@PAGEOFF
	bl _sel_registerName
	mov x1,x0
	mov x0,x19
	bl _objc_msgSend
	mov x19,x0
	adrp x0,getUBStr@PAGE
	add x0,x0,getUBStr@PAGEOFF
	bl _sel_registerName
	mov x1,x0
	mov x0,x19
	add x2,sp,#16
	bl _objc_msgSend
	add x0,sp,#32
	ldr x1,[sp,#56]
	mov x2,#16
	bl _memcpy
	ldr x2,[sp,#48]
	add x0,sp,#16
	mov x1,#32
	bl _CC_SHA256
	ldp x29,x30,[sp,#64]
	ldp x19,x20,[sp]
	add sp,sp,#80
	ret
; x0: class
.createNC:
	sub sp,sp,#32
	stp x29,x30,[sp,#16]
	stp x21,x22,[sp]
	mov x22,x1
	adrp x1,sel.1new@PAGE
	ldr x1,[x1,sel.1new@PAGEOFF]
	bl _objc_msgSend
	mov x21,x0
	adrp x0,allocSel@PAGE
	ldr x1,[x0,allocSel@PAGEOFF]
	adrp x0,_OBJC_CLASS_$_UINavigationController@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UINavigationController@GOTPAGEOFF]
	bl _objc_msgSend
	mov x2,x21
	adrp x1,sel.initwrvc@PAGE
	ldr x1,[x1,sel.initwrvc@PAGEOFF]
	bl _objc_msgSend
	str x0,[x22]
	mov x0,x21
	ldp x21,x22,[sp]
	ldp x29,x30,[sp,#16]
	add sp,sp,#32
	ret

_ios_app_exit:
	sub sp,sp,#64
	stp x29,x30,[sp,#48]
	str x19,[sp,#32]
	adrp x0,UIDismissSceneAction_str@PAGE
	add x0,x0,UIDismissSceneAction_str@PAGEOFF
	bl _objc_getClass
	cbnz x0,L_ios_app_exit.graceful
	bl _exit
L_ios_app_exit.graceful:
	mov x9,x0
	adrp x0,__NSConcreteStackBlock@GOTPAGE
	ldr x0,[x0,__NSConcreteStackBlock@GOTPAGEOFF]
	mov x1,#0x60000000
	adrp x2,_exit@GOTPAGE
	ldr x2,[x2,_exit@GOTPAGEOFF]
	adrp x3,plainBlockDescriptor@PAGE
	add x3,x3,plainBlockDescriptor@PAGEOFF
	stp x0,x1,[sp]
	stp x2,x3,[sp,#16]
	mov x0,x9
	adrp x1,allocSel@PAGE
	ldr x1,[x1,allocSel@PAGEOFF]
	bl _objc_msgSend
	mov x19,x0
	mov x0,xzr
	mov x1,xzr
	bl _dispatch_get_global_queue
	mov x3,x0
	mov x0,x19
	adrp x1,sel.initWithInfoEtc@PAGE
	ldr x1,[x1,sel.initWithInfoEtc@PAGEOFF]
	mov x2,xzr
	mov x4,sp
	fmov d0,#0.0
	bl _objc_msgSend
	mov x2,x0
	adrp x0,_OBJC_CLASS_$_NSSet@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_NSSet@GOTPAGEOFF]
	adrp x1,sel.setWithObject@PAGE
	ldr x1,[x1,sel.setWithObject@PAGEOFF]
	bl _objc_msgSend
	mov x19,x0
	adrp x0,_OBJC_CLASS_$_UIApplication@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_UIApplication@GOTPAGEOFF]
	adrp x1,sel.sharedApp@PAGE
	ldr x1,[x1,sel.sharedApp@PAGEOFF]
	bl _objc_msgSend
	adrp x1,sel._mainScene@PAGE
	ldr x1,[x1,sel._mainScene@PAGEOFF]
	bl _objc_msgSend
	adrp x1,sel.sendActions@PAGE
	ldr x1,[x1,sel.sendActions@PAGEOFF]
	mov x2,x19
	bl _objc_msgSend
	ldr x19,[sp,#32]
	ldp x29,x30,[sp,#48]
	add sp,sp,#64
	ret
____isOSVersionAtLeast:
	sub sp,sp,#48
	stp x29,x30,[sp,#32]
	stp x0,x1,[sp]
	stp x2,xzr,[sp,#16]
	adrp x0,_OBJC_CLASS_$_NSProcessInfo@GOTPAGE
	ldr x0,[x0,_OBJC_CLASS_$_NSProcessInfo@GOTPAGEOFF]
	adrp x1,sel.processInfo@PAGE
	ldr x1,[x1,sel.processInfo@PAGEOFF]
	bl _objc_msgSend
	adrp x1,sel.iOSAtLeast@PAGE
	ldr x1,[x1,sel.iOSAtLeast@PAGEOFF]
	mov x2,sp
	bl _objc_msgSend
	ldp x29,x30,[sp,#32]
	add sp,sp,#48
	ret

.section __TEXT,__cstring,cstring_literals
UIDismissSceneAction_str:
.asciz "UIDismissSceneAction"
UISceneConfiguration_str:
.asciz "UISceneConfiguration"
UIDevice_str:
.asciz "UIDevice"
UIWindow_str:
.asciz "UIWindow"
UISceneDelegate_str:
.asciz "UISceneDelegate"
uiresponderclass:
.asciz "SceneDelegateBase"
curDevStr:
.asciz "currentDevice"
idForVendStr:
.asciz "identifierForVendor"
getUBStr:
.asciz "getUUIDBytes:"
sceneName:
.asciz "SceneDelegate"
sceneInitSign:
.asciz "v@:@@@"
appFinSign:
.asciz "B@:@@"
sceneConfSign:
.asciz "@@:@@"
noParamSign:
.asciz "v@:"
tokenFile:
.asciz "/token"
UIWindowType:
.asciz "@\"UIWindow\""
TStr:
.asciz "T"
C_CStr:
.asciz "C"
IOPUUID:
.asciz "IOPlatformUUID"
IOPExpDev:
.asciz "IOPlatformExpertDevice"
agreeStr:
.asciz "Agree"
declineStr:
.asciz "Decline"
licenseStr:
#if !defined(LICENSE) || (LICENSE != LICENSE_NONFREE)
.asciz "License"
#else
.asciz "Terms of Use"
#endif
defaultConfigurationStr:
.asciz "Default Configuration"
fallback_license_url:
.asciz "https://raw.githubusercontent.com/Torrekie/Battman/master/Battman/license/license.html"
emptystr:
.space 1
mime_html:
.asciz "text/html"
js_disable_sharedworker:
.asciz "delete window.SharedWorker;"

.section __DATA,__cfstring
.p2align 3
emptycfstr:
	.quad   ___CFConstantStringClassReference
	.long   1992
	.space  4
	.quad   emptystr
	.quad   0

.section __DATA,__const
.p2align 3
plainBlockDescriptor:
	.quad 0
	.quad 32
"1ImpBlockDescriptor":
	.quad 0
	.quad 40
iOS13ver:
	.quad 13
	.quad 0
	.quad 0
	.quad 0

.section __DATA,__common
.global _graceful,_gWindow,_THEPATH,_THENUM
.p2align 3
_graceful:
	.quad 0
_gWindow:
	.quad 0
_THEPATH:
	.quad 0
_THENUM:
	.quad 0
.lfd.0:
	.quad 0
.lfd.1:
	.quad 0
.lfd.s:
	.quad 0
.osSupportsUIScene:
	.quad 0
;selectors
.section __TEXT,__objc_methname,cstring_literals
meth.makeKeyAndVisible:
	.asciz "makeKeyAndVisible"
m..sceneInit:
	.asciz "scene:willConnectToSession:options:"
m.setRootVC:
	.asciz "setRootViewController:"
newMeth:
	.asciz "new"
setWindowStr:
	.asciz "setWindow:"
.m.initWithWS:
	.asciz "initWithWindowScene:"
m.1alloc:
	.asciz "alloc"
.m.arrwobjs:
	.asciz "arrayWithObjects:count:"
.m.setRootVCs:
	.asciz "setViewControllers:animated:"
m.initWithRootVC:
	.asciz "initWithRootViewController:"
m.window:
	.asciz "window"
m.class:
	.asciz "class"
m.lhtmlstring:
	.asciz "loadHTMLString:baseURL:"
m.ceta:
	.asciz "constraintEqualToAnchor:"
m.salg:
	.asciz "safeAreaLayoutGuide"
m.topAnchor:
	.asciz "topAnchor"
m.leadingAnchor:
	.asciz "leadingAnchor"
m.trailingAnchor:
	.asciz "trailingAnchor"
m.bottomAnchor:
	.asciz "bottomAnchor"
m.setActive:
	.asciz "setActive:"
meth.view:
	.asciz "view"
meth.loadView:
	.asciz "loadView"
meth.addSubview:
	.asciz "addSubview:"
meth.tamic:
	.asciz "setTranslatesAutoresizingMaskIntoConstraints:"
m.frame:
	.asciz "frame"
m.setFrame:
	.asciz "setFrame:"
m.actionWithTitleEtc:
	.asciz "actionWithTitle:image:identifier:handler:"
m.initWithPrimaryAction:
	.asciz "initWithPrimaryAction:"
m.setLBBI:
	.asciz "setLeftBarButtonItem:"
m.setTitle:
	.asciz "setTitle:"
m.sharedApp:
	.asciz "sharedApplication"
m.suspend:
	.asciz "suspend"
m.topItem:
	.asciz "topItem"
m.navBar: .asciz "navigationBar"
m.navItem: .asciz "navigationItem"
m.initWithTSTA: .asciz "initWithTitle:style:target:action:"
m.invoke: .asciz "invoke"
m.copy:
	.asciz "copy"
m.setRBBI: .asciz "setRightBarButtonItem:"
m.bounds: .asciz "bounds"
m.initWithFrame: .asciz "initWithFrame:"
m.dataWithContentsOfURL: .asciz "dataWithContentsOfURL:"
m.initWithData_encoding: .asciz "initWithData:encoding:"
m.loadRequest: .asciz "loadRequest:"
m.requestWithURL: .asciz "requestWithURL:"
m.initWithFrameConfiguration: .asciz "initWithFrame:configuration:"
m.userContentController: .asciz "userContentController"
m.addUserScript: .asciz "addUserScript:"
m.initWithSourceInjectionTime: .asciz "initWithSource:injectionTime:forMainFrameOnly:"
m.loadHTMLStringBaseURL: .asciz "loadHTMLString:baseURL:"
m.systemBackgroundColor: .asciz "systemBackgroundColor"
m.setBackgroundColor: .asciz "setBackgroundColor:"
m.respondsToSelector: .asciz "respondsToSelector:"
m.setOpaque: .asciz "setOpaque:"
m.whiteColor: .asciz "whiteColor"


.section __DATA,__objc_selrefs,literal_pointers,no_dead_strip
.p2align 3
sel.makeKeyAndVisible:
	.quad meth.makeKeyAndVisible
s..sceneInit:
	.quad m..sceneInit
s.setRootVC:
	.quad m.setRootVC
sel.1new:
	.quad newMeth
sel.setWindow:
	.quad setWindowStr
initWithWS:
	.quad .m.initWithWS
allocSel:
	.quad m.1alloc
.sel.setRootVCs:
	.quad .m.setRootVCs
.sel.arrwobjs:
	.quad .m.arrwobjs
sel.initwrvc:
	.quad m.initWithRootVC
sel.window:
	.quad m.window
sel.class:
.quad m.class
sel.loadHTMLString:
.quad m.lhtmlstring
sel.ceta:
.quad m.ceta
sel.salg:
.quad m.salg
sel.topAnchor:
.quad m.topAnchor
sel.leadingAnchor:
.quad m.leadingAnchor
sel.trailingAnchor:
.quad m.trailingAnchor
sel.bottomAnchor:
.quad m.bottomAnchor
sel.setActive:
.quad m.setActive
sel.view:
.quad meth.view
sel.loadView:
.quad meth.loadView
sel.addSubview:
.quad meth.addSubview
sel.tamic:
.quad meth.tamic
sel.frame:
	.quad m.frame
sel.setFrame:
	.quad m.setFrame
sel.actionWithTitleEtc: .quad m.actionWithTitleEtc
sel.initWithPrimaryAction: .quad m.initWithPrimaryAction
sel.setLBBI: .quad m.setLBBI
sel.setTitle: .quad m.setTitle
sel.sharedApp: .quad m.sharedApp
sel.suspend: .quad m.suspend
sel.topItem: .quad m.topItem
sel.navItem: .quad m.navItem
sel.navBar: .quad m.navBar
sel.initWithTSTA: .quad m.initWithTSTA
sel.invoke: .quad m.invoke
sel.copy: .quad m.copy
sel.setRBBI: .quad m.setRBBI
sel.anyObject: .quad m.anyObject
sel.delegate: .quad m.delegate
sel.connectedScenes: .quad m.connectedScenes
sel.keyWindow: .quad m.keyWindow
sel.setHidden: .quad m.setHidden
sel.confScene: .quad m.confScene
finishLaunching_sel: .quad m.finLaunching
sel.iOSAtLeast: .quad m.iOSAtLeast
sel.initWithNameEtSessionRole: .quad m.ss_initWithNameEtc
sel.processInfo: .quad m.processInfo
sel.role: .quad m.role
sel.initWithInfoEtc: .quad m.initWithInfoEtc
sel._mainScene: .quad m._mainScene
sel.sendActions: .quad m.sendActions
sel.setWithObject: .quad m.setWithObject
sel.initWithBBSI: .quad m.initWithBBSI
sel.setItems: .quad m.setItems
sel.bounds: .quad m.bounds
sel.initWithFrame: .quad m.initWithFrame
sel.initWithData_encoding: .quad m.initWithData_encoding
sel.dataWithContentsOfURL: .quad m.dataWithContentsOfURL
sel.requestWithURL: .quad m.requestWithURL
sel.loadRequest: .quad m.loadRequest
sel.initWithFrameConfiguration: .quad m.initWithFrameConfiguration
sel.userContentController: .quad m.userContentController
sel.addUserScript: .quad m.addUserScript
sel.initWithSourceInjectionTime: .quad m.initWithSourceInjectionTime
sel.loadHTMLStringBaseURL: .quad m.loadHTMLStringBaseURL
sel.systemBackgroundColor: .quad m.systemBackgroundColor
sel.setBackgroundColor: .quad m.setBackgroundColor
sel.respondsToSelector: .quad m.respondsToSelector
sel.setOpaque: .quad m.setOpaque
sel.whiteColor: .quad m.whiteColor

.section __TEXT,__objc_methname,cstring_literals
m.setItems:
	.asciz "setItems:"
m.initWithBBSI:
	.asciz "initWithBarButtonSystemItem:target:action:"
m.initWithInfoEtc:
	.asciz "initWithInfo:timeout:forResponseOnQueue:withHandler:"
m._mainScene:
	.asciz "_mainScene"
m.sendActions:
	.asciz "sendActions:"
m.setWithObject:
	.asciz "setWithObject:"
m.processInfo:
	.asciz "processInfo"
m.role:
	.asciz "role"
m.iOSAtLeast:
	.asciz "isOperatingSystemAtLeastVersion:"
m.ss_initWithNameEtc:
	.asciz "initWithName:sessionRole:"
m.finLaunching:
	.asciz "application:didFinishLaunchingWithOptions:"
m.confScene:
	.asciz "application:configurationForConnectingSceneSession:options:"
m.keyWindow:
	.asciz "keyWindow"
m.setHidden:
	.asciz "setHidden:"
m.connectedScenes:
	.asciz "connectedScenes"
m.anyObject:
	.asciz "anyObject"
m.delegate:
	.asciz "delegate"

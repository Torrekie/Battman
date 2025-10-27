#pragma once

// FIXME: Seperate typedefs to their own headers
typedef struct objc_object NSObject;
typedef NSObject UIView;
typedef UIView UIWindow;
typedef NSObject UIViewController;
typedef NSObject UIScene;
typedef UIScene UIWindowScene;
typedef NSObject UIApplication;
typedef UIViewController UIAlertController;
typedef UIViewController UITableViewController;
typedef NSObject UIAlertAction;
typedef UIView UILabel;
typedef UIView UITableView;
typedef UIView UITableViewCell;
typedef NSObject NSIndexPath;
typedef NSObject UIColor;

typedef long NSInteger;
typedef double NSTimeInterval;

#define _DefineMethod_Type_Mapper(type,name) type name
#define _DefineMethod_TypeOnly_Mapper(type,n) COMMA() type
#define _DefineMethod_Value_Mapper(t,name) COMMA() name
#define _DefineMethod(selftype,selfobj,ret_type,name,sel,...) static inline ret_type name(selftype IF(AND(HAS_ARGS(__VA_ARGS__),HAS_ARGS(selftype)))( COMMA() ) MAP_WITH_ID(_DefineMethod_Type_Mapper,COMMA,__VA_ARGS__)) { return ((ret_type(*)(id,SEL MAP_WITH_ID(_DefineMethod_TypeOnly_Mapper,EMPTY,__VA_ARGS__)))objc_msgSend)(selfobj,oselector(sel) MAP_WITH_ID(_DefineMethod_Value_Mapper,EMPTY,__VA_ARGS__)); }

#define DefineObjcMethod(...) _DefineMethod(id self,self,__VA_ARGS__)
#define DefineClassMethod(class,...) _DefineMethod(,(id)oclass(class),__VA_ARGS__)

#include "./NSObject.h"
#include "./UIView.h"
#include "./UIWindow.h"
#include "./UIViewController.h"
#include "./UIApplication.h"
#include "./UIScene.h"
#include "./UIAlertController.h"
#include "./UITableViewController.h"
#include "./NSIndexPath.h"
#include "./UIColor.h"
#include "./UILabel.h"
#include "./UITableView.h"
#include "./NSTimer.h"

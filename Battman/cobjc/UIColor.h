#pragma once
#include "./cobjc.h"

// UIColor+compat.h
DefineClassMethod(UIColor, UIColor*, UIColorLinkColor, compatLinkColor);

DefineObjcMethod(CGColorRef, UIColorGetCGColor, CGColor);

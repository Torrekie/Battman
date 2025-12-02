//
//  IOMFB_interaction.h
//  Battman
//
//  Created by Torrekie on 2025/6/26.
//

#ifndef IOMFB_interaction_h
#define IOMFB_interaction_h

#include <stdio.h>
#include "../iokitextern.h"

#if __has_include(<IOKit/graphics/IOMobileFramebufferTypes.h>)
#include <IOKit/graphics/IOMobileFramebufferTypes.h>
#else
typedef struct __IOMobileFramebuffer *IOMobileFramebufferRef;
#endif

__BEGIN_DECLS

double iomfb_primary_screen_temperature(void);
const char *iomfb_primary_screen_panel_id(void);

__END_DECLS

#endif /* IOMFB_interaction_h */

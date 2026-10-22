#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Shows the Mbs-owned controls on the current document window.  These controls
// are independent of the vendor ribbon state and only dispatch Mbs-owned
// actions (account, AI and local history).
void MbsStartNativeToolbar(void);

#ifdef __cplusplus
}
#endif

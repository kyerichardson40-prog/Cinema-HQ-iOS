#include <assert.h>
#include "SMUSafeRect.h"
int main(void) {
    CGRect full=CGRectMake(0,0,430,932),out;
    assert(SMUAdjustFrame(full,full,59,0,34,0,&out));
    assert(CGRectEqualToRect(out,CGRectMake(0,59,430,839)));
    // Repeated layout/setFrame must not move the view twice.
    for (int i=0;i<100;i++) { assert(SMUAdjustFrame(out,full,59,0,34,0,&out)); assert(CGRectEqualToRect(out,CGRectMake(0,59,430,839))); }
    assert(SMUAdjustFrame(full,full,0,0,0,0,&out));assert(CGRectEqualToRect(full,out));
    CGRect landscape=CGRectMake(0,0,932,430);
    assert(SMUAdjustFrame(landscape,landscape,0,59,21,59,&out));
    assert(CGRectEqualToRect(out,CGRectMake(59,0,814,409)));
    CGRect modal=CGRectMake(0,0,430,500);
    assert(!SMUAdjustFrame(modal,full,59,0,34,0,&out));assert(CGRectEqualToRect(modal,out));
    assert(!SMUAdjustFrame(full,full,1000,0,0,0,&out));assert(CGRectEqualToRect(full,out));
    assert(!SMUAdjustFrame(full,full,NAN,0,0,0,&out));assert(CGRectEqualToRect(full,out));
    return 0;
}

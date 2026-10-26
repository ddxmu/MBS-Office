#define MBS_UI_ACTIONS_TEST
#include "../src/MbsUiActions.mm"

static NSString *bannerText;
static int getterCalls;
kso_qt::QString bannerContent(const void *) __asm__("__ZNK2kd8KDBanner14getContentTextEv");
kso_qt::QString drTipContent(const void *) __asm__("__ZN20KxDrTipContentWidget21getCurTipsContentTextEv");
kso_qt::QString bannerContent(const void *) { ++getterCalls; return literal(bannerText); }
kso_qt::QString drTipContent(const void *) { ++getterCalls; return literal(bannerText); }

int main() { @autoreleasepool {
    auto *widget=(kso_qt::QWidget *)&getterCalls;
    bannerText=@"限时优惠，大会员低至0.4元/天，畅享AI生成PPT、AI排版等全部AI权益";
    assert(MbsIsAiPromotionBanner(widget,@"kd::KDBanner"));
    assert(MbsIsAiPromotionBanner(widget,@"KxDrTipContentWidget"));
    assert(getterCalls==2);
    assert(!MbsIsAiPromotionBanner(widget,@"KxDrTipWidget"));
    assert(!MbsIsAiPromotionBanner(widget,@"QLabel"));
    assert(getterCalls==2);
    for (NSString *text in @[@"文档尚未保存",@"安全警告：宏已禁用",@"发生异常，文档已恢复",@"网络连接异常，请稍后重试",@"限时优惠",@"大会员权益",@"AI权益"]) {
        bannerText=text;
        assert(!MbsIsAiPromotionBanner(widget,@"kd::KDBanner"));
        assert(!MbsIsAiPromotionBanner(widget,@"KxDrTipContentWidget"));
    }
    bannerText=@"限时优惠，畅享全部AI权益";
    assert(MbsIsAiPromotionBanner(widget,@"kd::KDBanner"));
    puts("PASS exact banner classes and promotion text; document, safety, recovery and network notices preserved");
} }

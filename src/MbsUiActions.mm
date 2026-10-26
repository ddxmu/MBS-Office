#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "MbsLocalAccount.h"
#import "MbsAccountEntry.h"
#import "MbsWebsiteRouting.h"
#import "MbsUpdates.h"
#import "MbsEditorAuthorization.h"
#import "MbsNativeLoginRecovery.h"
#import "MbsLoginHitTarget.h"
#include <string.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>

namespace kso_qt {
class __attribute__((visibility("hidden"))) QString {
public: const void *data;
    explicit QString(const void *p):data(p){} ~QString(){}
    __attribute__((visibility("default"))) QString &operator=(const QString&);
};
class __attribute__((visibility("hidden"))) QVariant {
public: alignas(8) unsigned char data[16];
    __attribute__((visibility("default"))) QVariant(bool);
    __attribute__((visibility("default"))) QVariant(const QString &);
    __attribute__((visibility("default"))) ~QVariant();
    __attribute__((visibility("default"))) QString toString() const;
    __attribute__((visibility("default"))) int toInt(bool * = nullptr) const;
};
class QObject { public: QVariant property(const char*)const; bool setProperty(const char*,const QVariant&); };
class QWidget : public QObject { public:
    void setToolTip(const QString &); void setAccessibleName(const QString &);
    void updateGeometry(); void setVisible(bool); void show();
};
struct WidgetListData { int ref,allocation,begin,end; QWidget *items[1]; };
void disposeWidgetList(WidgetListData *) __asm__("__ZN6kso_qt9QListData7disposeEPNS0_4DataE");
class __attribute__((visibility("hidden"))) WidgetList {
public: WidgetListData *data;
    ~WidgetList() {
        if (data && data->ref!=-1 && __atomic_sub_fetch(&data->ref,1,__ATOMIC_ACQ_REL)==0) disposeWidgetList(data);
    }
};
class QApplication { public: static WidgetList allWidgets(); };
class QEvent;
class QMetaObject { public: const char *className()const; QObject *cast(QObject *)const; };
class QCoreApplication { public: static bool notifyInternal2(QObject*,QEvent*); };
class QLabel { public: static const QMetaObject staticMetaObject; void setText(const QString&); };
class QAbstractButton { public: static const QMetaObject staticMetaObject; void setText(const QString&); };
class QMouseEvent;
}
class KLiteClickableLabel;
class KPromeHeaderAvatar;
class KPromeHeaderAuthTip;
class KAppEntryWidget;
void labelSetText(void*,const kso_qt::QString&) __asm__("__ZN6kso_qt6QLabel7setTextERKNS_7QStringE");
void buttonSetText(void*,const kso_qt::QString&) __asm__("__ZN6kso_qt15QAbstractButton7setTextERKNS_7QStringE");
void widgetSetVisibleOriginal(kso_qt::QWidget *,bool) __asm__("__ZN6kso_qt7QWidget10setVisibleEb");
void widgetShowOriginal(kso_qt::QWidget *) __asm__("__ZN6kso_qt7QWidget4showEv");
void widgetToolTipOriginal(kso_qt::QWidget *,const kso_qt::QString &) __asm__("__ZN6kso_qt7QWidget10setToolTipERKNS_7QStringE");
struct MbsQtPoint { int x,y; };
MbsQtPoint widgetMapToGlobal(const kso_qt::QWidget *,const MbsQtPoint &) __asm__("__ZNK6kso_qt7QWidget11mapToGlobalERKNS_6QPointE");
void nativeColorCtor(void *,unsigned) __asm__("__ZN6kso_qt6QColorC1Ej");
void nativeDrawTextOriginal(void *,const void *,const kso_qt::QString &,int,const void *,const kso_qt::QString &,const void *,int,const kso_qt::QString &,const void *,const void *,const double &,int) __asm__("__ZN11KDrawHelper8drawTextEPN6kso_qt8QPainterERKNS0_5QRectERKNS0_7QStringEiRKNS0_5QFontES8_PKNS0_12QStyleOptionENS0_2Qt13TextElideModeES8_RKNS_18KDrawTextColorArgsERKNS0_6QColorERKdi");
void buttonMouseReleaseOriginal(kso_qt::QAbstractButton*,kso_qt::QMouseEvent*) __asm__("__ZN6kso_qt15QAbstractButton17mouseReleaseEventEPNS_11QMouseEventE");
void clickableLabelMouseReleaseOriginal(void*,kso_qt::QMouseEvent*) __asm__("__ZN19KLiteClickableLabel17mouseReleaseEventEPN6kso_qt11QMouseEventE");
void headerAvatarMouseReleaseOriginal(void*,kso_qt::QMouseEvent*) __asm__("__ZN18KPromeHeaderAvatar17mouseReleaseEventEPN6kso_qt11QMouseEventE");
void headerAuthTipMouseReleaseOriginal(void*,kso_qt::QMouseEvent*) __asm__("__ZN19KPromeHeaderAuthTip17mouseReleaseEventEPN6kso_qt11QMouseEventE");
void appEntryMouseReleaseOriginal(void*,kso_qt::QMouseEvent*) __asm__("__ZN15KAppEntryWidget17mouseReleaseEventEPN6kso_qt11QMouseEventE");
void unloginedButtonClickOriginal(void*) __asm__("__ZN18KPromeHeaderAvatar22onUnloginedButtonClickEv");
void promeGuideLoginOriginal(void*) __asm__("__ZN12KxMainWindow17onPromeGuideLoginEv");
void headerAvatarClickedOriginal(void*,const kso_qt::QString&) __asm__("__ZN18KPromeHeaderAvatar7clickedERKN6kso_qt7QStringE");
void headerAvatarPointClickedOriginal(void*,const void*,const kso_qt::QString&) __asm__("__ZN18KPromeHeaderAvatar7clickedERKN6kso_qt6QPointERKNS0_7QStringE");
void headAvatarClickedOriginal(void*,const kso_qt::QString&) __asm__("__ZN18KPromeHeaderAvatar19onHeadAvatarClickedERKN6kso_qt7QStringE");
bool desktopOpenUrlOriginal(const void*) __asm__("__ZN6kso_qt16QDesktopServices7openUrlERKNS_4QUrlE");
kso_qt::QString qurlPathOriginal(const void*,int) __asm__("__ZNK6kso_qt4QUrl4pathENS_6QFlagsINS0_25ComponentFormattingOptionEEE");
kso_qt::QString qurlHostOriginal(const void*,int) __asm__("__ZNK6kso_qt4QUrl4hostENS_6QFlagsINS0_25ComponentFormattingOptionEEE");
struct Data { int ref,len;unsigned allocation,padding;long offset; };
static const struct { Data h; unsigned short text[1]; } empty={{-1,0,0,0,24},{0}};
static NSString *read(const kso_qt::QString &value) {
    const auto *d=(const Data*)value.data;
    if(!d||d->len<0)return @"";
    return [[NSString alloc] initWithCharacters:(const unichar*)((const char*)d+d->offset) length:d->len];
}
static const void *MbsNativeAccountTextColor(const void *option,const kso_qt::QString &text,const void *color,void *blue) {
    // The bundled KPromeHeaderAvatar constructs QStyleOptionComplex(1,
    // 0x08000f04). Restrict the color override to that header's account text.
    int type=0; if (option) memcpy(&type,(const char *)option+sizeof(int),sizeof(type));
    if (type!=0x08000f04 || !MbsIsAccountEntryText(read(text))) return color;
    nativeColorCtor(blue,0xff006ce7); return blue;
}
static void nativeDrawAccountText(void *painter,const void *rect,const kso_qt::QString &text,int flags,const void *font,const kso_qt::QString &theme,const void *option,int elide,const kso_qt::QString &state,const void *colorArgs,const void *color,const double &opacity,int mode) {
    alignas(8) unsigned char blue[32];
    color=MbsNativeAccountTextColor(option,text,color,blue);
    nativeDrawTextOriginal(painter,rect,text,flags,font,theme,option,elide,state,colorArgs,color,opacity,mode);
}
static kso_qt::QString literal(NSString *value) {
    static NSMutableDictionary<NSString*,NSValue*>*cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSMutableDictionary dictionary];});
    @synchronized(cache) {
        if(!cache[value]) {auto*d=(Data*)calloc(1,24+(value.length+1)*2);d->ref=-1;d->len=(int)value.length;d->offset=24;
            [value getCharacters:(unichar*)(d+1) range:NSMakeRange(0,value.length)];cache[value]=[NSValue valueWithPointer:d];}
        return kso_qt::QString(cache[value].pointerValue);
    }
}
static BOOL isRemovedAssistantText(NSString *text) {
    return [text containsString:@"灵犀"] || [text containsString:@"超级派"];
}
static BOOL MbsIsAiPromotionText(NSString *text) {
    return [text containsString:@"限时优惠"] &&
        ([text containsString:@"大会员"] || [text containsString:@"AI权益"]);
}
static NSString *updated(NSString *text) {
    if ([text isEqualToString:@"WPS"]) return @"Mbs";
    if ([text isEqualToString:@"稻壳资源"] || [text isEqualToString:@"Docer Resource Shop"]) return @"Mbs资源";
    if (isRemovedAssistantText(text)) return @"";
    NSString *result = [text stringByReplacingOccurrencesOfString:@"免费使用企业版" withString:@"版本升级"];
    return result;
}
static void widgetToolTip(kso_qt::QWidget *widget,const kso_qt::QString &text) {
    NSString *value=read(text);
    if ([value isEqualToString:@"稻壳资源"] || [value isEqualToString:@"Docer Resource Shop"])
        widgetToolTipOriginal(widget,literal(@"Mbs资源"));
    else widgetToolTipOriginal(widget,text);
}
static BOOL isUpgradeText(NSString *text) {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [value isEqualToString:@"升级"] || [value isEqualToString:@"版本升级"];
}
static BOOL isBlockedRemoteHost(NSString *host) {
    return [host isEqualToString:@"personal.local.wps.cn"] ||
           [host isEqualToString:@"personal.local.wps.com"] ||
           [host isEqualToString:@"personal.local.wps365.com"];
}
static BOOL isLegacyAssistantHost(NSString *host) {
    return [host isEqualToString:@"lingxi.kdocs.cn"] ||
           [host isEqualToString:@"lingxi.wps.cn"];
}
static BOOL isLegacyLoginURL(NSURL *url) {
    return [url.host.lowercaseString isEqualToString:@"account.wps.cn"] &&
           [url.path isEqualToString:@"/wpsmaclogin"];
}
static IMP MbsWorkspaceOpenURLOriginal;
static BOOL MbsWorkspaceOpenURL(id self, SEL selector, NSURL *url) {
    NSString *host = url.host.lowercaseString;
    if (isLegacyLoginURL(url)) {
        // Background SDK navigation is not a request to open the browser.
        // Only the Mbs form's explicit web-login button opens our login page.
        return YES;
    }
    if (isLegacyAssistantHost(host)) return YES;
    if (isBlockedRemoteHost(host)) return YES;
    if (!MbsWorkspaceOpenURLOriginal) return NO;
    if (MbsIsLegacyWebsiteURL(url)) url=[NSURL URLWithString:MbsWebsiteHome];
    return ((BOOL (*)(id, SEL, NSURL *))MbsWorkspaceOpenURLOriginal)(self, selector, url);
}
static void InstallMbsWorkspaceURLHook(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method method = class_getInstanceMethod([NSWorkspace class], @selector(openURL:));
        if (method) {
            MbsWorkspaceOpenURLOriginal = method_getImplementation(method);
            method_setImplementation(method, (IMP)MbsWorkspaceOpenURL);
        }
    });
}
static NSString *accountText(kso_qt::QObject *object,NSString *text) {
    if (![text isEqualToString:@"立即登录"]) return text;
    object->setProperty("mbsAccountEntry",kso_qt::QVariant(true));
    return MbsAccountEntryTitle();
}
static void MbsScheduleAccountEntryRefresh(void);
static void labelText(kso_qt::QLabel*label,const kso_qt::QString&text) {
    NSString *value=read(text),*replacement=accountText((kso_qt::QObject *)label,updated(value));
    if(![value isEqualToString:replacement])label->setText(literal(replacement));else label->setText(text);
    if ([value containsString:@"当前编辑内容尚未保存"] || MbsIsAiPromotionText(value)) MbsScheduleAccountEntryRefresh();
}
static void buttonText(kso_qt::QAbstractButton*button,const kso_qt::QString&text) {
    NSString *value=read(text),*replacement=accountText((kso_qt::QObject *)button,updated(value));
    if(![value isEqualToString:replacement])button->setText(literal(replacement));else button->setText(text);
}
static NSString *property(kso_qt::QObject*object,const char*key) {
    auto variant=object->property(key);auto value=variant.toString();NSString *result=read(value);
    value=kso_qt::QString(&empty);return result;
}
static NSString *className(kso_qt::QObject*object) {
    // Verified QtKso 5.12 arm64: QObject::property at 0x207ea4 calls
    // metaObject through vtable slot zero. QObjectPrivate::setParent_helper
    // at 0x200464 reads q_ptr at +8 and parent at +16.
    auto **table=*(void***)object;
    auto meta=((const kso_qt::QMetaObject*(*)(const void*))table[0])(object);
    const char *name=meta?meta->className():nullptr;
    return name?[NSString stringWithUTF8String:name]:@"";
}
static BOOL MbsIsPresentationThemeEntry(kso_qt::QObject *object) {
    if (![className(object) isEqualToString:@"KStatusButton"] ||
        (![property(object,"text") isEqualToString:@"WPS"] &&
         ![property(object,"mbsResourceEntry") isEqualToString:@"true"])) return NO;
    void *data=nullptr; memcpy(&data,(char *)object+8,8);
    auto *parent=data?*(kso_qt::QObject **)((char *)data+16):nullptr;
    if (!parent || ![className(parent) isEqualToString:@"KStatusBar"]) return NO;
    memcpy(&data,(char *)parent+8,8);
    auto *window=data?*(kso_qt::QObject **)((char *)data+16):nullptr;
    return window && [className(window) isEqualToString:@"KxWppMainWindow"];
}
static BOOL MbsIsLegacyAccountPanel(NSString *name) {
    return [name isEqualToString:@"KPromeAccountPanelWidget"] ||
        [name isEqualToString:@"KPromeAccountPanelKeletonWidgetV2"];
}
static BOOL MbsIsAiPromotionBanner(kso_qt::QWidget *widget,NSString *name) {
    const char *symbol=nullptr;
    if ([name isEqualToString:@"kd::KDBanner"]) symbol="_ZNK2kd8KDBanner14getContentTextEv";
    else if ([name isEqualToString:@"KxDrTipContentWidget"]) symbol="_ZN20KxDrTipContentWidget21getCurTipsContentTextEv";
    if (!symbol) return NO;
    // These exported getters return the same nontrivial QString ABI as
    // QVariant::toString above. Leave every non-promotional notice intact.
    auto getText=(kso_qt::QString (*)(const void *))dlsym(RTLD_DEFAULT,symbol);
    if (!getText) return NO;
    auto text=getText(widget);
    BOOL promotional=MbsIsAiPromotionText(read(text));
    text=kso_qt::QString(&empty);
    return promotional;
}
static void widgetSetVisible(kso_qt::QWidget *widget,bool visible) {
    NSString *kind=className(widget);
    widget->setVisible(visible && !MbsIsLegacyAccountPanel(kind) && !MbsIsAiPromotionBanner(widget,kind));
    if (visible) MbsScheduleAccountEntryRefresh();
}
static void widgetShow(kso_qt::QWidget *widget) {
    NSString *kind=className(widget);
    if (!MbsIsLegacyAccountPanel(kind) && !MbsIsAiPromotionBanner(widget,kind)) widget->show();
    MbsScheduleAccountEntryRefresh();
}
static void MbsRefreshNativeAvatar(kso_qt::QWidget *widget,NSString *title,NSString *email) {
    // These native header APIs only update its painted name and layout;
    // account validity continues to come from the Mbs session.
    auto setName=(void (*)(void *,const kso_qt::QString &))dlsym(RTLD_DEFAULT,"_ZN18KPromeHeaderAvatar16setLoginUserNameERKN6kso_qt7QStringE");
    auto showText=(void (*)(void *,bool))dlsym(RTLD_DEFAULT,"_ZN18KPromeHeaderAvatar14setTextVisibleEb");
    if (!setName || !showText) return;
    setName(widget,literal(title)); showText(widget,true);
    widget->setProperty("mbsAccountEntry",kso_qt::QVariant(true));
    widget->setAccessibleName(literal(title));
    widget->setToolTip(literal(email)); widget->updateGeometry();
}

static auto MbsPdfNoticeSwitch() -> void (*)(void *,bool) {
    // This private API is stripped from the shipped export table. Resolve only
    // the inspected arm64 image, using both its UUID and instruction fingerprint.
    static const unsigned char uuid[]={0x94,0x0f,0x36,0x91,0x17,0x7e,0x30,0xf1,0xbb,0xe1,0x0e,0xaa,0xdd,0x55,0x80,0x4b};
    static const unsigned char code[]={0xf4,0x4f,0xbe,0xa9,0xfd,0x7b,0x01,0xa9,0xfd,0x43,0x00,0x91,0xf4,0x03,0x00,0xaa,0x08,0xec,0x42,0xf9,0xf3,0x03,0x01,0x2a};
    for (uint32_t i=0;i<_dyld_image_count();++i) {
        const char *name=_dyld_get_image_name(i);
        if (!name || !strstr(name,"/pdfmain.framework/")) continue;
        const auto *header=(const mach_header_64 *)_dyld_get_image_header(i);
        if (header->magic!=MH_MAGIC_64 || header->cputype!=CPU_TYPE_ARM64) continue;
        const auto *command=(const load_command *)(header+1);
        bool matched=false;
        for (uint32_t j=0;j<header->ncmds;++j) {
            if (command->cmd==LC_UUID && !memcmp(((const uuid_command *)command)->uuid,uuid,sizeof(uuid))) matched=true;
            command=(const load_command *)((const char *)command+command->cmdsize);
        }
        const auto *entry=(const unsigned char *)header+0x12cbbc;
        if (matched && !memcmp(entry,code,sizeof(code))) return (void (*)(void *,bool))entry;
    }
    return nullptr;
}
static void MbsRefreshPdfTrialNotice(kso_qt::QWidget *view) {
    bool active=MbsHasVerifiedEditorLicense();
    if (!active && ![property(view,"mbsPdfTrialNoticeDisabled") isEqualToString:@"true"]) return;
    // Use the original view's notice switch; it hides an existing notice and
    // disables its later display without affecting the document's dirty state.
    auto disable=MbsPdfNoticeSwitch();
    if (!disable) return;
    disable(view,active);
    view->setProperty("mbsPdfTrialNoticeDisabled",kso_qt::QVariant(active));
}

static void MbsRefreshAccountEntries(void) {
    static BOOL updating;
    if (updating) return;
    updating=YES;
    NSString *title=MbsAccountEntryTitle(),*email=MbsAccountEntryEmail();
    auto widgets=kso_qt::QApplication::allWidgets();
    auto *list=widgets.data;
    for (int index=list->begin;index<list->end;++index) {
        auto *widget=list->items[index];
        NSString *kind=className(widget);
        if ([kind isEqualToString:@"KStatusButton"] && [property(widget,"text") isEqualToString:@"WPS"]) {
            if (MbsIsPresentationThemeEntry(widget)) widget->setProperty("mbsResourceEntry",kso_qt::QVariant(true));
            widget->setProperty("text",kso_qt::QVariant(literal(@"Mbs")));
            continue;
        }
        if (MbsIsPresentationThemeEntry(widget)) {
            if (![property(widget,"mbsResourceEntry") isEqualToString:@"true"])
                widget->setProperty("mbsResourceEntry",kso_qt::QVariant(true));
            if (![property(widget,"text") isEqualToString:@"WPS"]) continue;
            widget->setProperty("text",kso_qt::QVariant(literal(@"Mbs")));
            continue;
        }
        if ([kind isEqualToString:@"KxPdfView"]) { MbsRefreshPdfTrialNotice(widget); continue; }
        if (MbsIsLegacyAccountPanel(kind) || MbsIsAiPromotionBanner(widget,kind)) { widget->setVisible(false); continue; }
        if ([kind isEqualToString:@"KPromeHeaderAvatar"]) {
            MbsRefreshNativeAvatar(widget,title,email); continue;
        }
        BOOL button=kso_qt::QAbstractButton::staticMetaObject.cast(widget)!=nullptr;
        BOOL label=!button && kso_qt::QLabel::staticMetaObject.cast(widget)!=nullptr;
        if (!button && !label) continue;
        NSString *text=property(widget,"text");
        if ([text isEqualToString:@"WPS"]) {
            if (button) ((kso_qt::QAbstractButton *)widget)->setText(literal(@"Mbs"));
            else ((kso_qt::QLabel *)widget)->setText(literal(@"Mbs"));
            continue;
        }
        if (![text isEqualToString:@"立即登录"] && ![property(widget,"mbsAccountEntry") isEqualToString:@"true"]) continue;
        widget->setProperty("mbsAccountEntry",kso_qt::QVariant(true));
        if (![text isEqualToString:title]) {
            if (button) ((kso_qt::QAbstractButton *)widget)->setText(literal(title));
            else ((kso_qt::QLabel *)widget)->setText(literal(title));
        }
        widget->setToolTip(literal(email));
    }
    updating=NO;
}

static void MbsScheduleAccountEntryRefresh(void) {
    static BOOL pending;
    if (pending) return;
    pending=YES;
    dispatch_async(dispatch_get_main_queue(), ^{ pending=NO; MbsRefreshAccountEntries(); });
}
static BOOL MbsIsNativeAccountEntry(kso_qt::QObject *object,NSString *text) {
    return [text isEqualToString:@"立即登录"] ||
        (MbsIsAccountEntryText(text) && [property(object,"mbsAccountEntry") isEqualToString:@"true"]);
}
static NSArray<NSValue *> *MbsNativeAvatarFrames(NSRect windowFrame) {
    NSMutableArray *frames=[NSMutableArray array];
    auto widgets=kso_qt::QApplication::allWidgets(); auto *list=widgets.data;
    for (int index=list->begin;index<list->end;++index) {
        auto *widget=list->items[index];
        if (![className(widget) isEqualToString:@"KPromeHeaderAvatar"] ||
            ![property(widget,"visible") isEqualToString:@"true"]) continue;
        int width=widget->property("width").toInt(),height=widget->property("height").toInt();
        if (width<20 || width>220 || height<12 || height>64) continue;
        MbsQtPoint point=widgetMapToGlobal(widget,{0,0});
        NSRect frame=NSMakeRect(point.x,NSMaxY(NSScreen.screens.firstObject.frame)-point.y-height,width,height);
        if (NSContainsRect(windowFrame,frame)) [frames addObject:[NSValue valueWithRect:frame]];
    }
    return frames;
}
static BOOL MbsSuppressLegacyAccountHover(kso_qt::QObject *receiver,unsigned short type) {
    if (type!=5 && type!=10 && type!=127 && type!=129) return NO;
    for (int depth=0;receiver && depth<7;++depth) {
        NSString *name=className(receiver);
        if ([name isEqualToString:@"KPromeHeaderAvatar"] || [name isEqualToString:@"KPromeHeaderAuthTip"] ||
            MbsIsNativeAccountEntry(receiver,property(receiver,"text"))) return YES;
        void *data=nullptr; memcpy(&data,(char *)receiver+8,8);
        auto *parent=data?*(kso_qt::QObject **)((char *)data+16):nullptr;
        if (parent==receiver) break;
        receiver=parent;
    }
    return NO;
}
static bool routeClick(kso_qt::QObject*receiver,kso_qt::QEvent*event) {
    unsigned short type=0;if(event)memcpy(&type,(char*)event+16,2);
    if (type==17 && NSThread.isMainThread) {
        auto finish=(void (*)(void *))dlsym(RTLD_DEFAULT,"MbsScheduleNativeLegacyLogin");
        if (finish) finish(receiver);
    }
    if (NSThread.isMainThread && MbsSuppressLegacyAccountHover(receiver,type)) return true;
    if(type==3 && NSThread.isMainThread) {
        @autoreleasepool {
            kso_qt::QObject*object=receiver;
            for(int depth=0;object&&depth<7;++depth) {
                NSString *name=className(object),*text=property(object,"text");
                if (MbsIsPresentationThemeEntry(object)) {
                    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:MbsWebsiteHome]]; return true;
                }
                if ((depth == 0 && MbsIsNativeAccountEntry(object,text)) || [name isEqualToString:@"KPromeHeaderAvatar"]) {
                    MbsOpenAccountEntry(); return true;
                }
                if (isRemovedAssistantText(text)) return true;
                if (isUpgradeText(text)) {
                    MbsShowUpdates();return true;
                }
                void *data=nullptr;memcpy(&data,(char*)object+8,8);
                auto *parent=data?*(kso_qt::QObject**)((char*)data+16):nullptr;
                if(parent==object)break;object=parent;
            }
        }
    }
    bool handled=kso_qt::QCoreApplication::notifyInternal2(receiver,event);
    // Document toolbars are built after the window becomes key. Refresh after
    // their actual Show event rather than relying on the earlier window event.
    if (NSThread.isMainThread && type==17) MbsScheduleAccountEntryRefresh();
    return handled;
}
static void buttonMouseRelease(kso_qt::QAbstractButton *button,kso_qt::QMouseEvent *event) {
    NSString *text=property((kso_qt::QObject*)button,"text");
    if (isRemovedAssistantText(text)) return;
    if (isUpgradeText(text)) {
        MbsShowUpdates();
        return;
    }
    if (MbsIsNativeAccountEntry((kso_qt::QObject *)button,text) || [text isEqualToString:@"登录"]) {
        MbsOpenAccountEntry();
        return;
    }
    buttonMouseReleaseOriginal(button,event);
}
static bool maybeShowLocalAccount(void *button) {
    NSString *text=property((kso_qt::QObject*)button,"text");
    if (isRemovedAssistantText(text)) return true;
    if (isUpgradeText(text)) {
        MbsShowUpdates(); return true;
    }
    if (MbsIsNativeAccountEntry((kso_qt::QObject *)button,text) || [text isEqualToString:@"登录"]) {
        MbsOpenAccountEntry(); return true;
    }
    return false;
}
static void clickableLabelMouseRelease(void *button,kso_qt::QMouseEvent *event) {
    if (!maybeShowLocalAccount(button)) clickableLabelMouseReleaseOriginal(button,event);
}
static void headerAvatarMouseRelease(void *button,kso_qt::QMouseEvent *event) {
    MbsOpenAccountEntry();
}
static void headerAuthTipMouseRelease(void *button,kso_qt::QMouseEvent *event) {
    if (!maybeShowLocalAccount(button)) headerAuthTipMouseReleaseOriginal(button,event);
}
static void appEntryMouseRelease(void *button,kso_qt::QMouseEvent *event) {
    if (!maybeShowLocalAccount(button)) appEntryMouseReleaseOriginal(button,event);
}
static void MbsShowAccountForUserClick(void) {
    NSEvent *event = NSApp.currentEvent;
    if ((event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp ||
         event.type == NSEventTypeKeyDown) &&
        NSProcessInfo.processInfo.systemUptime - event.timestamp < 1.0) MbsOpenAccountEntry();
}
static void unloginedButtonClick(void *self) {
    MbsShowAccountForUserClick();
}
static void promeGuideLogin(void *self) {
    MbsShowAccountForUserClick();
}
static void headerAvatarClicked(void *self,const kso_qt::QString &value) {
    MbsShowAccountForUserClick();
}
static void headerAvatarPointClicked(void *self,const void *point,const kso_qt::QString &value) {
    MbsShowAccountForUserClick();
}
static void headAvatarClicked(void *self,const kso_qt::QString &value) {
    MbsShowAccountForUserClick();
}
static bool desktopOpenUrl(const void *url) {
    if (url) {
        auto hostValue = qurlHostOriginal(url, 0);
        NSString *host = read(hostValue);
        auto pathValue = qurlPathOriginal(url, 0);
        if ([host.lowercaseString isEqualToString:@"account.wps.cn"] &&
            [read(pathValue) isEqualToString:@"/wpsmaclogin"]) {
            return true;
        }
        if (isLegacyAssistantHost(host)) return true;
        if (isBlockedRemoteHost(host)) return true;
        if (MbsIsLegacyWebsiteHost(host)) {
            [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:MbsWebsiteHome]];
            return true;
        }
    }
    return desktopOpenUrlOriginal(url);
}
struct Interpose {const void*replacement;const void*original;};
#ifndef MBS_UI_ACTIONS_TEST
__attribute__((used,section("__DATA,__interpose"))) static const Interpose actions[]={
    {(const void*)&labelText,(const void*)&labelSetText},
    {(const void*)&buttonText,(const void*)&buttonSetText},
    {(const void*)&buttonMouseRelease,(const void*)&buttonMouseReleaseOriginal},
    {(const void*)&clickableLabelMouseRelease,(const void*)&clickableLabelMouseReleaseOriginal},
    {(const void*)&headerAvatarMouseRelease,(const void*)&headerAvatarMouseReleaseOriginal},
    {(const void*)&headerAuthTipMouseRelease,(const void*)&headerAuthTipMouseReleaseOriginal},
    {(const void*)&appEntryMouseRelease,(const void*)&appEntryMouseReleaseOriginal},
    {(const void*)&unloginedButtonClick,(const void*)&unloginedButtonClickOriginal},
    {(const void*)&promeGuideLogin,(const void*)&promeGuideLoginOriginal},
    {(const void*)&headerAvatarClicked,(const void*)&headerAvatarClickedOriginal},
    {(const void*)&headerAvatarPointClicked,(const void*)&headerAvatarPointClickedOriginal},
    {(const void*)&headAvatarClicked,(const void*)&headAvatarClickedOriginal},
    {(const void*)&desktopOpenUrl,(const void*)&desktopOpenUrlOriginal},
    {(const void*)&routeClick,(const void*)&kso_qt::QCoreApplication::notifyInternal2},
    {(const void*)&widgetSetVisible,(const void*)&widgetSetVisibleOriginal},
    {(const void*)&widgetShow,(const void*)&widgetShowOriginal},
    {(const void*)&widgetToolTip,(const void*)&widgetToolTipOriginal},
    {(const void*)&nativeDrawAccountText,(const void*)&nativeDrawTextOriginal}
};
#endif
static id MbsLoginMouseMonitor;
static __weak NSWindow *MbsLoginPressedWindow;
static NSRect MbsLoginPressedFrame;
static void InstallMbsLoginMouseMonitor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (MbsLoginMouseMonitor) return;
        MbsLoginMouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp) handler:^NSEvent *(NSEvent *event) {
            NSWindow *window=event.window;
            NSPoint point=event.locationInWindow;
            if (event.type == NSEventTypeLeftMouseDown) {
                MbsLoginPressedWindow = nil;
                if (window.isVisible && window.contentView) {
                    NSPoint screen = [window convertPointToScreen:point];
                    BOOL headerOnly=![window.title isEqualToString:@"首页"];
                    NSArray *frames=[MbsLoginButtonFrames(window,window.frame,headerOnly)
                        arrayByAddingObjectsFromArray:MbsNativeAvatarFrames(window.frame)];
                    for (NSValue *value in frames) {
                        if (NSPointInRect(screen,value.rectValue)) {
                            MbsLoginPressedWindow = window; MbsLoginPressedFrame = value.rectValue;
                            return nil;
                        }
                    }
                }
            } else if (event.type == NSEventTypeLeftMouseUp && MbsLoginPressedWindow) {
                BOOL hit = window == MbsLoginPressedWindow &&
                    NSPointInRect([window convertPointToScreen:point],MbsLoginPressedFrame);
                MbsLoginPressedWindow = nil;
                if (hit) MbsOpenAccountEntry();
                return nil;
            }
            return event;
        }];
    });
}
#ifndef MBS_UI_ACTIONS_TEST
__attribute__((constructor)) static void startChecks() {
    InstallMbsWorkspaceURLHook();
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification*){MbsStartUpdateChecks();MbsStartAccountSession();}];
    InstallMbsLoginMouseMonitor();
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSNotificationName name in @[@"MbsLocalAccountDidChange",@"MbsEditorAuthorizationDidChange",NSWindowDidBecomeKeyNotification,NSApplicationDidFinishLaunchingNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                if ([name isEqualToString:NSWindowDidBecomeKeyNotification]) MbsStartAccountSession();
                MbsScheduleAccountEntryRefresh();
            }];
        }
        MbsScheduleAccountEntryRefresh();
    });
}
#endif

#import <AppKit/AppKit.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "MbsAiPanel.h"
#include "MbsLocalAccount.h"
#include "MbsUpdates.h"
#include "MbsAbout.h"
#include "MbsWebsiteRouting.h"

// ABI pinned to WPS 12.1.25867 / QtKso 5.12.12, arm64.
namespace kso_qt {
class __attribute__((visibility("hidden"))) QString {
public:
    const void *data;
    explicit QString(const void *value) : data(value) {}
    ~QString() {}
    __attribute__((visibility("default"))) QString &operator=(const QString &);
};
class __attribute__((visibility("hidden"))) QVariant {
public:
    alignas(8) unsigned char data[16];
    __attribute__((visibility("default"))) ~QVariant();
    __attribute__((visibility("default"))) QString toString() const;
};
class QObject {
public:
    QVariant property(const char *) const;
};
class QEvent;
class QCoreApplication {
public:
    static bool sendEvent(QObject *, QEvent *);
};
}
static_assert(sizeof(kso_qt::QString) == 8, "Unexpected QString ABI");
static_assert(sizeof(kso_qt::QVariant) == 16, "Unexpected QVariant ABI");

class KCommand {
public:
    kso_qt::QObject *host() const;
    void syncTrigger();
};
class KCommands {
public:
    KCommand *command(const kso_qt::QString &);
};
class KMainWindow {
public:
    static KMainWindow *getMainWindow(const kso_qt::QObject *);
    KCommands *commands();
};
class KCommandEvent {
public:
    static int CommandBeforeTrigger;
};

struct StringHeader {
    int referenceCount, length;
    unsigned allocation, padding;
    intptr_t offset;
};
static_assert(sizeof(StringHeader) == 24, "Unexpected Qt string header");
static const struct { StringHeader header; uint16_t text[1]; }
    emptyString = {{-1, 0, 0, 0, 24}, {0}};
static const struct { StringHeader header; uint16_t text[5]; }
    copyString = {{-1, 4, 0, 0, 24}, {'C', 'o', 'p', 'y', 0}};

static NSString *commandProperty(KCommand *command,const char *key)
{
    auto property = reinterpret_cast<kso_qt::QObject *>(command)->property(key);
    auto value = property.toString();
    const auto *header = static_cast<const StringHeader *>(value.data);
    NSString *result = nil;
    if (header && header->length >= 0) {
        const auto *text = reinterpret_cast<const unichar *>(
            reinterpret_cast<const char *>(header) + header->offset);
        result = [[NSString alloc] initWithCharacters:text length:header->length];
    }
    // Release the vendor-owned result through its real assignment operator.
    // The small bridge QString destructor is intentionally an ownership no-op.
    value = kso_qt::QString(&emptyString);
    return result;
}

struct AiCommand { const char *identifier; const char *operation; };
static const AiCommand aiCommands[] = {
    {"MbsAiSettings", "settings"},
    {"MbsAiPpt", "ppt"},
    {"MbsAiDocumentPpt", "document-ppt"},
    {"MbsAiOutlinePpt", "outline-ppt"},
    {"MbsAiSlide", "slide"},
    {"MbsAiSlides", "slides"},
    {"MbsAiImage", "image"},
    {"MbsAiWrite", "write"},
    {"MbsAiRewrite", "rewrite"},
    {"MbsAiExpand", "expand"},
    {"MbsAiShorten", "shorten"},
    {"MbsAiMore", "ask"},
    {"MbsAiHistory", "history"},
    {"About", "about"},
    {"RbFileMenuAbout", "about"},
    {"MbsLocalAccount", "account"},
    {"MbsUpdates", "updates"},
    {"MbsAiPolish", "polish"},
    {"MbsAiProofread", "proofread"},
    {"MbsAiTranslate", "translate"},
    {"MbsAiAsk", "ask"},
    {"MbsAiSummarize", "summarize"},
    // Existing, statically verified XML command IDs. The build replaces their
    // vendor command classes with ordinary commands for our own AI service.
    {"WpsAiModifyNew", "polish"},
    {"WpsAiModifyNewEmptyIcon", "polish"},
    {"WpsRbAiModifyNewEmptyIcon", "polish"},
    {"CheckSpellingToolBar_home_spell", "proofread"},
    {"TpAiSpellcheck_toolbar", "proofread"},
    {"wps_aispellcheck_selectfloat_refine", "proofread"},
    {"app_aiworddefinition_selectfloat_translate", "translate"},
    {"app_immersive_translate_drtip", "translate"},
    {"WpsChatDoc", "ask"},
    {"ProxyWpsChatDoc", "ask"},
    {"WpsAiReading", "ask"},
    {"app_aiworddefinition_selectfloat_explain", "ask"},
    {"WpsAiSummary", "summarize"},
    {"WpsArticleSummary", "summarize"},
    {"WpsAISummary", "summarize"},
    {"app_aiworddefinition_selectfloat_summarize", "summarize"}
};

static void debugCommand(NSString *identifier)
{
    if (!getenv("MBS_DEBUG_COMMANDS") || !identifier || identifier.length > 100) return;
    // Log only AI-related ASCII identifiers, never text, filenames, or paths.
    const char *prefixes[] = {"AI", "Ai", "ai_", "MbsAi", "Wps", "ProxyWps",
                             "CheckSpelling", "TpAi", "Copilot", "KCopilot", "Formula_AI"};
    bool relevant = false;
    for (const char *prefix : prefixes)
        if ([identifier hasPrefix:[NSString stringWithUTF8String:prefix]]) relevant = true;
    if (!relevant) return;
    for (NSUInteger i = 0; i < identifier.length; ++i) {
        unichar c = [identifier characterAtIndex:i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-' || c == ' ')) return;
    }
    fprintf(stderr, "Mbs AI command: %s\n", identifier.UTF8String);
}

static NSString *copySelection(KCommand *source)
{
    auto *host = source->host();
    if (!host) return @"";
    auto *window = KMainWindow::getMainWindow(host);
    auto *commands = window ? window->commands() : nullptr;
    if (!commands) return @"";
    auto *copy = commands->command(kso_qt::QString(&copyString));
    if (!copy) return @"";

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSMutableArray<NSPasteboardItem *> *saved = [NSMutableArray array];
    // If any representation cannot be materialized, keep the clipboard intact
    // and let the user enter text in the assistant instead.
    for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
        NSPasteboardItem *snapshot = [[NSPasteboardItem alloc] init];
        for (NSPasteboardType type in item.types) {
            NSData *data = [item dataForType:type];
            if (!data || ![snapshot setData:[data copy] forType:type]) return @"";
        }
        [saved addObject:snapshot];
    }

    NSString *selection = @"";
    @try {
        // Clearing first prevents a disabled/no-selection Copy command from
        // supplying old clipboard contents to an API request.
        [pasteboard clearContents];
        copy->syncTrigger();
        selection = [[pasteboard stringForType:NSPasteboardTypeString] copy] ?: @"";
    } @finally {
        [pasteboard clearContents];
        if (saved.count) [pasteboard writeObjects:saved];
    }
    return selection;
}

static bool aiSendEvent(kso_qt::QObject *receiver, kso_qt::QEvent *event)
{
    if (!event || KCommandEvent::CommandBeforeTrigger <= 0 ||
        KCommandEvent::CommandBeforeTrigger > UINT16_MAX)
        return kso_qt::QCoreApplication::sendEvent(receiver, event);
    auto *bytes = reinterpret_cast<unsigned char *>(event);
    uint16_t type;
    memcpy(&type, bytes + 16, sizeof(type));
    if (type != KCommandEvent::CommandBeforeTrigger)
        return kso_qt::QCoreApplication::sendEvent(receiver, event);
    KCommand *command;
    memcpy(&command, bytes + 24, sizeof(command));
    if (!command) return kso_qt::QCoreApplication::sendEvent(receiver, event);

    @autoreleasepool {
        NSString *identifier = commandProperty(command,"id");
        debugCommand(identifier);
        if ([identifier isEqualToString:@"TpDocerResourceShop"] ||
            [identifier isEqualToString:@"wppStatusDesignInfo"] ||
            [identifier isEqualToString:@"changeThemeSideWidget"] ||
            [identifier isEqualToString:@"changeThemeModalWidget"] ||
            MbsIsLegacyWebsiteURL([NSURL URLWithString:commandProperty(command,"url")])) {
            bytes[32] = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:MbsWebsiteHome]];
            });
            return true;
        }
        const char *operation = nullptr;
        for (const auto &entry : aiCommands) {
            if ([identifier isEqualToString:[NSString stringWithUTF8String:entry.identifier]]) {
                operation = entry.operation;
                break;
            }
        }
        if (!operation) return kso_qt::QCoreApplication::sendEvent(receiver, event);

        bytes[32] = 0; // This command is implemented by Mbs, not the vendor action.
        bool settings = strcmp(operation, "settings") == 0;
        bool account = strcmp(operation, "account") == 0;
        bool updates = strcmp(operation, "updates") == 0;
        bool about = strcmp(operation, "about") == 0;
        bool history = strcmp(operation, "history") == 0;
        NSString *selection = @"";
        if (!settings && !account && !updates && !about && !history && NSThread.isMainThread) {
            @try { selection = copySelection(command); }
            @catch (NSException *) { selection = @""; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (account) MbsShowLocalAccount();
            else if (about) MbsShowAbout();
            else if (updates) MbsShowUpdates();
            else if (settings) MbsShowAiSettings();
            else MbsShowAiAssistant(operation, selection.UTF8String);
        });
        return true;
    }
}

struct AiInterpose { const void *replacement; const void *original; };
__attribute__((used, section("__DATA,__interpose")))
static const AiInterpose aiEvents = {
    reinterpret_cast<const void *>(&aiSendEvent),
    reinterpret_cast<const void *>(&kso_qt::QCoreApplication::sendEvent)
};

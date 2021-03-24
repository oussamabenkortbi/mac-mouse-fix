//
// --------------------------------------------------------------------------
// RemapTableDataSource.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2021
// Licensed under MIT
// --------------------------------------------------------------------------
//

#import "RemapTableTranslator.h"
#import "Constants.h"
#import "UIStrings.h"
#import "SharedUtility.h"
#import "NSAttributedString+Additions.h"
#import "NSTextField+Additions.h"
#import "ConfigFileInterface_App.h"
#import "RemapTableController.h"

@interface RemapTableTranslator ()

@end

@implementation RemapTableTranslator

#pragma mark (Pseudo) Properties

NSTableView *_tableView;
//
+ (void)initializeWithTableView:(NSTableView *)tableView {
    _tableView = tableView;
}
+ (NSTableView *)tableView {
    return _tableView;
}
+ (RemapTableController *)controller {
    return (RemapTableController *)self.tableView.delegate;
}
+ (NSArray *)dataModel {
    return self.controller.dataModel;
}
+ (void)setDataModel:(NSArray *)newModel {
    self.controller.dataModel = newModel;
}

#pragma mark Define Effects Tables
// ^ Effects tables are one-to-one mappings between UI stirngs and effect dicts. The effect dicts encode the exact effect in a way the helper can read
// They are used to generate the popup button menus and relate between the data model (which contains effectDicts) and the UI (which contains UI stirngs)
// Effects tables are arrays of dictionaries called effect table entries. Table entries currently support the folling keys:
//  "ui" - The main UI string of the effect. This will be the title of the popupbutton-menu-item for the effect
//  "tool" - Tooltip of the popupbutton-menu-item
//  "dict" - The effect dict
//  "alternate" - If set to @YES, this entry will revealed by pressing a modifier key in the popupbutton menu
// ? TODO: Create constants for these keys
// There are also separatorTableEntry()s which become a separator in the popupbutton-menu generated from the effectsTable
// There are 3 different effectsTables for 3 different types of triggers

static NSDictionary *separatorEffectsTableEntry() {
    return @{@"noeffect": @"separator"};
}
// Hideablility doesn't seem to work on separators
//static NSDictionary *hideableSeparatorEffectsTableEntry() {
//    return @{@"noeffect": @"separator", @"hideable": @YES};
//}
static NSArray *getScrollEffectsTable() {
    NSArray *scrollEffectsTable = @[
        @{@"ui": @"Zoom in or out", @"tool": @"Zoom in or out in Safari, Maps, and other apps \nWorks like Pinch to Zoom on an Apple Trackpad" , @"dict": @{}
        },
        @{@"ui": @"Horizontal scroll", @"tool": @"Scroll horizontally \nNavigate pages in Safari, delete messages in Mail, and more \nWorks like swiping horizontally with 2 fingers on an Apple Trackpad" , @"dict": @{}
        },
//        @{@"ui": @"Rotate", @"tool": @"", @"dict": @{}},
//        @{@"ui": @"Precision Scroll", @"tool": @"", @"dict": @{}},
//        @{@"ui": @"Fast scroll", @"tool": @"", @"dict": @{}},
    ];
    return scrollEffectsTable;
}
static NSArray *getDragEffectsTable() {
    NSArray *dragEffectsTable = @[
        @{@"ui": @"Mission Control & Spaces", @"tool": @"Move your mouse: \n - Up to show Mission Control \n - Down to show Application Windows \n - Left or Right to move between Spaces" , @"dict": @{
                  kMFModifiedDragDictKeyType: kMFModifiedDragTypeThreeFingerSwipe,
        }},
//        @{@"ui": @"Scroll & navigate pages", @"tool": @"Scroll by moving your mouse in any direction \nNavigate pages in Safari, delete messages in Mail, and more, by moving your mouse horizontally \nWorks like swiping with 2 fingers on an Apple Trackpad" , @"dict": @{
//                  kMFModifiedDragDictKeyType: kMFModifiedDragTypeTwoFingerSwipe,
//        }},
//        separatorEffectsTableEntry(),
        @{@"ui": [NSString stringWithFormat:@"Click and Drag %@", [UIStrings getButtonString:3]],
          @"tool": [NSString stringWithFormat: @"Simulates clicking and dragging %@ \nUsed to rotate in some 3d software like Blender", getButtonStringToolTip(3)],
          @"hideable": @YES,
          @"dict": @{
                  kMFModifiedDragDictKeyType: kMFModifiedDragTypeFakeDrag,
                  kMFModifiedDragDictKeyFakeDragVariantButtonNumber: @3,
        }},
    ];
    return dragEffectsTable;
}
static NSArray *getOneShotEffectsTable(NSDictionary *buttonTriggerDict) {
    
    int buttonNumber = ((NSNumber *)buttonTriggerDict[kMFButtonTriggerKeyButtonNumber]).intValue;
    
    NSArray *oneShotEffectsTable = @[
        @{@"ui": @"Mission Control", @"tool": @"Show Mission Control", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeSymbolicHotkey,
                  kMFActionDictKeyGenericVariant: @(kMFSHMissionControl)
        }},
        @{@"ui": @"Application Windows", @"tool": @"Show all windows of the active app", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeSymbolicHotkey,
                  kMFActionDictKeyGenericVariant: @(kMFSHAppExpose)
        }},
        @{@"ui": @"Show Desktop", @"tool": @"Show the desktop", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeSymbolicHotkey,
                  kMFActionDictKeyGenericVariant: @(kMFSHShowDesktop)
        }},
        separatorEffectsTableEntry(),
        @{@"ui": @"Launchpad", @"tool": @"Open Launchpad", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeSymbolicHotkey,
                  kMFActionDictKeyGenericVariant: @(kMFSHLaunchpad)
        }},
        separatorEffectsTableEntry(),
        @{@"ui": @"Look Up", @"tool": @"Look up words in the Dictionary, Quick Look files in Finder, and more... \nWorks like Force Touch on an Apple Trackpad", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeSymbolicHotkey,
                  kMFActionDictKeyGenericVariant: @(kMFSHLookUp)
        }},
        @{@"ui": @"Smart Zoom", @"tool": @"Zoom in or out in Safari and other apps \nSimulates a two-finger double tap on an Apple Trackpad", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeSmartZoom,
        }},
        @{@"ui": @"Open Link in New Tab",
          @"tool": [NSString stringWithFormat:@"Open links in a new tab, paste text in the Terminal, and more... \nSimulates clicking %@", getButtonStringToolTip(3)],
          @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeMouseButtonClicks,
                  kMFActionDictKeyMouseButtonClicksVariantButtonNumber: @3,
                  kMFActionDictKeyMouseButtonClicksVariantNumberOfClicks: @1,
          }},
        separatorEffectsTableEntry(),
        @{@"ui": @"Move Left a Space", @"tool": @"Move one Space to the left", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeSymbolicHotkey,
                  kMFActionDictKeyGenericVariant: @(kMFSHMoveLeftASpace)
        }},
        @{@"ui": @"Move Right a Space", @"tool": @"Move one Space to the right", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeSymbolicHotkey,
                  kMFActionDictKeyGenericVariant: @(kMFSHMoveRightASpace)
        }},
        separatorEffectsTableEntry(),
        @{@"ui": @"Back", @"tool": @"Go back one page in Safari and other apps", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeNavigationSwipe,
                  kMFActionDictKeyGenericVariant: kMFNavigationSwipeVariantLeft
        }},
        @{@"ui": @"Forward", @"tool": @"Go forward one page in Safari and other apps", @"dict": @{
                  kMFActionDictKeyType: kMFActionDictTypeNavigationSwipe,
                  kMFActionDictKeyGenericVariant: kMFNavigationSwipeVariantRight
        }},
    ];
    
    if (buttonNumber != 3) { // We already have the "Open Link in New Tab" entry for button 3
        NSDictionary *buttonClickEntry = @{
           @"ui": [NSString stringWithFormat:@"%@ Click", [UIStrings getButtonString:buttonNumber]],
           @"tool": [NSString stringWithFormat:@"Simulate Clicking %@", getButtonStringToolTip(buttonNumber)],
           @"hideable": @YES,
           @"dict": @{
               kMFActionDictKeyType: kMFActionDictTypeMouseButtonClicks,
               kMFActionDictKeyMouseButtonClicksVariantButtonNumber: @(buttonNumber),
               kMFActionDictKeyMouseButtonClicksVariantNumberOfClicks: @1,
           }
        };
        NSMutableArray *temp = oneShotEffectsTable.mutableCopy;
        [temp insertObject:buttonClickEntry atIndex:9];
        oneShotEffectsTable = temp;
    }
    
    return oneShotEffectsTable;
}
// Convenience functions for effects tables
+ (NSDictionary *)getEntryFromEffectsTable:(NSArray *)effectsTable withEffectDict:(NSDictionary *)effectDict {
    NSIndexSet *inds = [effectsTable indexesOfObjectsPassingTest:^BOOL(NSDictionary * _Nonnull tableEntry, NSUInteger idx, BOOL * _Nonnull stop) {
        return [tableEntry[@"dict"] isEqualToDictionary:effectDict];
    }];
    NSAssert(inds.count == 1, @"");
    // TODO: React well to inds.count == 0, to support people editing remaps dict by hand (If I'm reallyyy bored)
    NSDictionary *effectsTableEntry = (NSDictionary *)effectsTable[inds.firstIndex];
    return effectsTableEntry;
}
+ (NSDictionary *)getEntryFromEffectsTable:(NSArray *)effectsTable withUIString:(NSString *)uiString {
    NSIndexSet *inds = [effectsTable indexesOfObjectsPassingTest:^BOOL(NSDictionary * _Nonnull tableEntry, NSUInteger idx, BOOL * _Nonnull stop) {
        return [tableEntry[@"ui"] isEqualToString:uiString];
    }];
    NSAssert(inds.count == 1, @"");
    NSDictionary *effectsTableEntry = effectsTable[inds.firstIndex];
    return effectsTableEntry;
}
+ (NSArray *)getEffectsTableForRemapsTableEntry:(NSDictionary *)tableEntry {
    // Get info about what kind of trigger we're dealing with
    NSString *triggerType = @""; // Options "oneShot", "drag", "scroll"
    id triggerValue = tableEntry[kMFRemapsKeyTrigger];
    if ([triggerValue isKindOfClass:NSDictionary.class]) {
        triggerType = @"button";
    } else if ([triggerValue isKindOfClass:NSString.class]) {
        NSString *triggerValueStr = (NSString *)triggerValue;
        if ([triggerValueStr isEqualToString:kMFTriggerDrag]) {
            triggerType = @"drag";
        } else if ([triggerValueStr isEqualToString:kMFTriggerScroll]) {
            triggerType = @"scroll";
        } else {
            NSAssert(YES, @"Can't determine trigger type.");
        }
    }
    // Get effects Table
    NSArray *effectsTable;
    if ([triggerType isEqualToString:@"button"]) {
        // We determined that trigger value is a dict -> convert to dict
        NSDictionary *buttonTriggerDict = (NSDictionary *)triggerValue;
        effectsTable = getOneShotEffectsTable(buttonTriggerDict);
    } else if ([triggerType isEqualToString:@"drag"]) {
        effectsTable = getDragEffectsTable();
    } else if ([triggerType isEqualToString:@"scroll"]) {
        effectsTable = getScrollEffectsTable();
    } else {
        NSAssert(NO, @"");
    }
    return effectsTable;
}

#pragma mark - Fill the tableView

+ (NSTableCellView *)getEffectCellWithRowDict:(NSDictionary *)rowDict {
    
    rowDict = rowDict.mutableCopy; // Not sure if necessary
    NSArray *effectsTable = [self getEffectsTableForRemapsTableEntry:rowDict];
    // Create trigger cell and fill out popup button contained in it
    NSTableCellView *triggerCell = [self.tableView makeViewWithIdentifier:@"effectCell" owner:nil];
    // Get popup button
    NSPopUpButton *popupButton = triggerCell.subviews[0];
    // Delete existing menu items from IB
    [popupButton removeAllItems];
    // Iterate oneshot effects table and fill popupButton
    for (NSDictionary *effectDict in effectsTable) {
        NSMenuItem *i;
        if ([effectDict[@"noeffect"] isEqualToString: @"separator"]) {
            i = (NSMenuItem *)NSMenuItem.separatorItem;
        } else {
            i = [[NSMenuItem alloc] initWithTitle:effectDict[@"ui"] action:@selector(setConfigToUI:) keyEquivalent:@""];
            i.toolTip = effectDict[@"tool"];
            if ([effectDict[@"alternate"] isEqualTo:@YES]) {
                i.alternate = YES;
                i.keyEquivalentModifierMask = NSEventModifierFlagOption;
            }
            if ([effectDict[@"hideable"] isEqualTo:@YES]) {
                NSMenuItem *h = [[NSMenuItem alloc] init];
                h.view = [[NSView alloc] initWithFrame:NSZeroRect];
                [popupButton.menu addItem:h];
                i.alternate = YES;
                i.keyEquivalentModifierMask = NSEventModifierFlagOption;
            }
            i.target = self.tableView.delegate;
        }
        [popupButton.menu addItem:i];
    }
    
    // Select popup button item corresponding to datamodel
    // Get effectDict from datamodel
    NSDictionary *effectDict = rowDict[kMFRemapsKeyEffect];
    if (effectDict) { // When inserting new rows through AddMode, there is no effectDict at first
        // Get title for effectDict from effectsTable
        NSDictionary *effectsTableEntry = [self getEntryFromEffectsTable:effectsTable withEffectDict:effectDict];
        NSString *title = effectsTableEntry[@"ui"];
        // Select item with title
        [popupButton selectItemWithTitle:title];
    }
    
    return triggerCell;
}

+ (NSTableCellView *)getTriggerCellWithRowDict:(NSDictionary *)rowDict {
    rowDict = rowDict.mutableCopy; // This is necessary for some of this hacky mess to work // However, this is not a deep copy, so the _dataModel is still changed when we change some nested object. Watch out!
    
    // Define Data-to-UI-String mappings
    NSDictionary *clickLevelToUIString = @{
        @1: @"",
        @2: @"Double ",
        @3: @"Triple ",
    };
    
    // Get trigger string from data
    NSMutableAttributedString *tr;
    NSMutableAttributedString *trTool;
    id triggerGeneric = rowDict[kMFRemapsKeyTrigger];
    
    if ([triggerGeneric isKindOfClass:NSDictionary.class]) { // Trigger is button input
        
        // Get relevant values from button trigger dict
        NSDictionary *trigger = (NSDictionary *)triggerGeneric;
        NSNumber *btn = trigger[kMFButtonTriggerKeyButtonNumber];
        NSNumber *lvl = trigger[kMFButtonTriggerKeyClickLevel];
        NSString *dur = trigger[kMFButtonTriggerKeyDuration];
        
        // Generate substrings from data
        
        // lvl
        NSString *levelStr = (NSString *)clickLevelToUIString[lvl];
        if (!levelStr) {
            levelStr = [NSString stringWithFormat:@"%@", lvl];
        }
        if (lvl.intValue < 1) { // 0 or smaller
            @throw [NSException exceptionWithName:@"Invalid click level" reason:@"Remaps contain invalid click level" userInfo:@{@"Trigger dict containing invalid value": trigger}];
        }
        // dur
        NSString *durationStr;
        if ([dur isEqualToString:kMFButtonTriggerDurationClick]) {
            durationStr = @"Click ";
        } else if ([dur isEqualToString:kMFButtonTriggerDurationHold]) {
            if (lvl.intValue == 1) {
                durationStr = @"Hold ";
            } else {
                durationStr = @"Click and Hold ";
            }
        }
        if (!durationStr) {
            @throw [NSException exceptionWithName:@"Invalid duration" reason:@"Remaps contain invalid duration" userInfo:@{@"Trigger dict containing invalid value": trigger}];
        }
        // btn
        NSString * buttonStr = [UIStrings getButtonString:btn.intValue];
        NSString * buttonStrTool = getButtonStringToolTip(btn.intValue);
        if (btn.intValue < 1) {
            @throw [NSException exceptionWithName:@"Invalid button number" reason:@"Remaps contain invalid button number" userInfo:@{@"Trigger dict containing invalid value": trigger}];
        }
        
        // Form trigger string from substrings
        
        NSString *trRaw = [NSString stringWithFormat:@"%@%@%@", levelStr, durationStr, buttonStr];
        NSString *trToolRaw = [NSString stringWithFormat:@"%@%@%@", levelStr, durationStr, buttonStrTool];
        
        // Turn into attributedString and highlight button substrings
        tr = [self addBoldForSubstring:buttonStr inString:trRaw];
        trTool = [self addBoldForSubstring:buttonStrTool inString:trToolRaw];
        
    } else if ([triggerGeneric isKindOfClass:NSString.class]) { // Trigger is drag or scroll
        // We need part of the modification precondition to form the main trigger string here.
        //  E.g. if our precondition for a modified drag is single click button 3, followed by double click button 4, we want the string to be "Click Middle Button + Double Click and Drag Button 4", where the "Click Middle Button + " substring follows the format of a regular modification precondition string (we compute those further down) but the "Double Click and Drag Button 4" substring, which is also called the "trigger string" follows a different format which we compute here.
        // Get button strings from last button precond, or, if no button preconds exist, get keyboard modifier string
        NSString *levelStr = @"";
        NSString *clickStr = @"";
        NSString *buttonStr = @"";
        NSString *keyboardModStr = @"";
        NSString *buttonStrTool = @"";
        NSString *keyboardModStrTool = @"";
        
        // Extract last button press from button-modification-precondition. If it doesn't exist, get kb mod string
        NSDictionary *lastButtonPress;
        NSMutableArray *buttonPressSequence = ((NSArray *)rowDict[kMFRemapsKeyModificationPrecondition][kMFModificationPreconditionKeyButtons]).mutableCopy;
        NSNumber *keyboardModifiers = rowDict[kMFRemapsKeyModificationPrecondition][kMFModificationPreconditionKeyKeyboard];
        if (buttonPressSequence) {
            lastButtonPress = buttonPressSequence.lastObject;
            [buttonPressSequence removeLastObject];
            rowDict[kMFRemapsKeyModificationPrecondition][kMFModificationPreconditionKeyButtons] = buttonPressSequence;
            // Generate Level, click, and button strings based on last button press from sequence
            NSNumber *btn = lastButtonPress[kMFButtonModificationPreconditionKeyButtonNumber];
            NSNumber *lvl = lastButtonPress[kMFButtonModificationPreconditionKeyClickLevel];
            levelStr = clickLevelToUIString[lvl];
            clickStr = @"Click ";
            buttonStr = [UIStrings getButtonString:btn.intValue];
            buttonStrTool = getButtonStringToolTip(btn.intValue);
        } else if (keyboardModifiers) {
            // Extract keyboard modifiers
            keyboardModStr = getKeyboardModifierString(keyboardModifiers);
            keyboardModStrTool = getKeyboardModifierStringToolTip(keyboardModifiers);
            rowDict[kMFRemapsKeyModificationPrecondition][kMFModificationPreconditionKeyKeyboard] = nil;
        } else {
            @throw [NSException exceptionWithName:@"No precondition" reason:@"Modified drag or scroll has no preconditions" userInfo:@{@"Precond dict": (rowDict[kMFRemapsKeyModificationPrecondition])}];
        }
        
        // Get trigger string
        NSString *triggerStr;
        NSString *trigger = (NSString *)triggerGeneric;
        if ([trigger isEqualToString:kMFTriggerDrag]) {
            triggerStr = @"and Drag ";
        } else if ([trigger isEqualToString:kMFTriggerScroll]) {
            triggerStr = @"and Scroll ";
        } else {
            @throw [NSException exceptionWithName:@"Unknown string trigger value" reason:@"The value for the string trigger key is unknown" userInfo:@{@"Trigger value": trigger}];
        }
        
        // Form full trigger cell string from substrings
        
        NSString *trRaw = [NSString stringWithFormat:@"%@%@%@%@%@", levelStr, clickStr, keyboardModStr, triggerStr, buttonStr];
        NSString *trToolRaw = [NSString stringWithFormat:@"%@%@%@%@%@", levelStr, clickStr, keyboardModStrTool, triggerStr, buttonStrTool];
        
        // Turn into attributedString and highlight button substrings
        tr = [self addBoldForSubstring:buttonStr inString:trRaw];
        trTool = [self addBoldForSubstring:buttonStrTool inString:trToolRaw];
        
    } else {
        NSLog(@"Trigger value: %@, class: %@", triggerGeneric, [triggerGeneric class]);
        @throw [NSException exceptionWithName:@"Invalid trigger value type" reason:@"The value for the trigger key is not a String and not a dictionary" userInfo:@{@"Trigger value": triggerGeneric}];
    }
    
    // Get keyboard modifier strings
    
    NSNumber *flags = (NSNumber *)rowDict[kMFRemapsKeyModificationPrecondition][kMFModificationPreconditionKeyKeyboard];
    NSString *kbModRaw = getKeyboardModifierString(flags);
    NSString *kbModTooltipRaw = getKeyboardModifierStringToolTip(flags);
    NSString *kbMod = @"";
    NSString *kbModTool = @"";
    if (![kbModRaw isEqualToString:@""]) {
        kbMod = [kbModRaw stringByAppendingString:@""]; // @"+ "
        kbModTool = [kbModTooltipRaw stringByAppendingString:@", then "];
    }
    
    // Get button modifier string
    
    NSMutableArray *buttonPressSequence = rowDict[kMFRemapsKeyModificationPrecondition][kMFModificationPreconditionKeyButtons];
    NSMutableArray *buttonModifierStrings = [NSMutableArray array];
    NSMutableArray *buttonModifierStringsTool = [NSMutableArray array];
    for (NSDictionary *buttonPress in buttonPressSequence) {
        NSNumber *btn = buttonPress[kMFButtonModificationPreconditionKeyButtonNumber];
        NSNumber *lvl = buttonPress[kMFButtonModificationPreconditionKeyClickLevel];
        NSString *levelStr;
        NSString *buttonStr;
        NSString *buttonStrTool;
        buttonStr = [UIStrings getButtonString:btn.intValue];
        buttonStrTool = getButtonStringToolTip(btn.intValue);
        levelStr = clickLevelToUIString[lvl];
        NSString *buttonModString = [NSString stringWithFormat:@"%@Click %@ + ", levelStr, buttonStr];
        NSString *buttonModStringTool = [NSString stringWithFormat:@"%@Click and Hold %@, then ", levelStr, buttonStrTool];
        [buttonModifierStrings addObject:buttonModString];
        [buttonModifierStringsTool addObject:buttonModStringTool];
    }
    NSString *btnMod = [buttonModifierStrings componentsJoinedByString:@""];
    NSString *btnModTool = [buttonModifierStringsTool componentsJoinedByString:@""];
    
    // Join all substrings to get result string
    NSMutableAttributedString *fullTriggerCellString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@%@", kbMod, btnMod]];
    NSMutableAttributedString *fullTriggerCellTooltipString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@%@", kbModTool, btnModTool]];
    [fullTriggerCellString appendAttributedString:tr];
    [fullTriggerCellTooltipString appendAttributedString:trTool];
    
    
    // Generate view and set string to view
    NSTableCellView *triggerCell = [self.tableView makeViewWithIdentifier:@"triggerCell" owner:nil];
    triggerCell.textField.attributedStringValue = fullTriggerCellString;
    triggerCell.textField.toolTip = fullTriggerCellTooltipString.string;
    return triggerCell;
}

# pragma mark - String generation helper functions

static NSString *getButtonStringToolTip(int buttonNumber) {
    NSDictionary *buttonNumberToUIString = @{
        @1: @"the Primary Mouse Button (also called the Left Mouse Button or Mouse Button 1)",
        @2: @"the Secondary Mouse Button (also called the Right Mouse Button or Mouse Button 2)",
        @3: @"the Middle Mouse Button (also called the Scroll Wheel Button or Mouse Button 3)",
    };
    NSString *buttonStr = buttonNumberToUIString[@(buttonNumber)];
    if (!buttonStr) {
        buttonStr = [NSString stringWithFormat:@"Mouse Button %@", @(buttonNumber)];
    }
    return buttonStr;
}

static NSString *getKeyboardModifierString(NSNumber *flags) {
    NSString *kb = @"";
    if (flags) {
        CGEventFlags f = flags.longLongValue;
        kb = [NSString stringWithFormat:@"%@%@%@%@ ",
              (f & kCGEventFlagMaskControl ?    @"^" : @""),
              (f & kCGEventFlagMaskAlternate ?  @"⌥" : @""),
              (f & kCGEventFlagMaskShift ?      @"⇧" : @""),
              (f & kCGEventFlagMaskCommand ?    @"⌘" : @"")];
    }
    return kb;
}
static NSString *getKeyboardModifierStringToolTip(NSNumber *flags) {
    NSString *kb = @"";
    if (flags) {
        CGEventFlags f = flags.longLongValue;
        kb = [NSString stringWithFormat:@"%@%@%@%@",
              (f & kCGEventFlagMaskControl ?    @"Control (^)-" : @""),
              (f & kCGEventFlagMaskAlternate ?  @"Option (⌥)-" : @""),
              (f & kCGEventFlagMaskShift ?      @"Shift (⇧)-" : @""),
              (f & kCGEventFlagMaskCommand ?    @"Command (⌘)-" : @"")];
    }
    if (kb.length > 0) {
        kb = [kb substringToIndex:kb.length-1]; // Delete trailing dash
//        kb = [kb stringByAppendingString:@" "]; // Append trailing space
        kb = [kb stringByReplacingOccurrencesOfString:@"-" withString:@" and "];
        kb = [@"Hold " stringByAppendingString:kb];
    }
    
    return kb;
}
+ (NSMutableAttributedString *)addBoldForSubstring:(NSString *)subStr inString:(NSString *)baseStr {
    
    NSMutableAttributedString *ret = [[NSMutableAttributedString alloc] initWithString:baseStr];
    NSFont *boldFont = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    NSRange subStrRange = [baseStr rangeOfString:subStr];
//    [ret addAttribute:NSFontAttributeName value:boldFont range:subStrRange]; // Commenting this out means the function doesn't do anything
    return ret;
}

@end
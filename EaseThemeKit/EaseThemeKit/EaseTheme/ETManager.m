//
//  SHEaseThemeManager.m
//  EaseThemeKit
//
//  Created by aKerdi on 2017/10/28.
//  Copyright © 2017年 XXT. All rights reserved.
//

#import "ETManager.h"
#import "EaseTheme.h"

UIKIT_EXTERN char *const kETSELHeader;
UIKIT_EXTERN char *const kETSELCon;
UIKIT_EXTERN NSString *const kET2DStateSELTail;
UIKIT_EXTERN NSString *const kET2DAnimatedSELTail;

UIKIT_EXTERN NSString *const kETArgBool;
UIKIT_EXTERN NSString *const kETArgFloat;
UIKIT_EXTERN NSString *const kETArgInt;
UIKIT_EXTERN NSString *const kETArgColor;
UIKIT_EXTERN NSString *const kETArgCGColor;
UIKIT_EXTERN NSString *const kETArgFont;
UIKIT_EXTERN NSString *const kETArgImage;
UIKIT_EXTERN NSString *const kETArgTextAttributes;
UIKIT_EXTERN NSString *const kETArgStatusBarStyle;
UIKIT_EXTERN NSString *const kETArgBarStyle;
UIKIT_EXTERN NSString *const kETArgTitle;
UIKIT_EXTERN NSString *const kETArgKeyboardAppearance;
UIKIT_EXTERN NSString *const kETArgActivityIndicatorViewStyle;


static NSString *kETFileExtensionPLIST = @"plist";
static NSString *kETFileExtensionJSON = @"json";
static NSString *kETFileExtensionZIP = @"zip";

static NSString *const kETImageExtensionPNG = @"png";
static NSString *const kETImageExtensionJPG = @"jpg";

static inline UIColor *(ETRGBHex)(NSUInteger hex) {
    return [UIColor colorWithRed:((float)((hex&0xFF0000)>>16))/255.0 green:((float)((hex&0xFF00)>>8))/255.0 blue:((float)((hex&0xFF)))/255.0 alpha:1.0];
}

SEL _Nullable getSelectorWithPattern(const char * _Nullable prefix, const char * _Nullable key, const char * _Nullable suffix) {
    size_t prefixLength = prefix ? strlen(prefix) : 0;
    size_t suffixLength = suffix ? strlen(suffix) : 0;
    
    char initial = key[0];
    if (prefixLength) initial = (char)toupper(initial);
    size_t initialLength = 1;
    
    const char *rest = key + initialLength;
    size_t restLength = strlen(rest);
    
    char selector[prefixLength + initialLength + restLength + suffixLength +1];
    memcpy(selector, prefix, prefixLength);
    selector[prefixLength] = initial;
    memcpy(selector + prefixLength + initialLength, rest, restLength);
    memcpy(selector + prefixLength + initialLength + restLength, suffix, suffixLength);
    selector[prefixLength + initialLength + restLength + suffixLength] = '\0';
    return sel_registerName(selector);
}

@interface ETManager ()
@property (nonatomic, strong) NSHashTable<EaseTheme *> *weakArray;


@end

@implementation ETManager

static NSString *_resourcesPath;

static NSDictionary *_themeDic;//缓存一份数据 shift时需要更改该缓存

static NSString *_currentThemeName;

static NSUInteger _currentThemeType;//来自于bundle 还是sandbox

static ETManager *_easeThemeManager;

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _easeThemeManager = [super allocWithZone:zone];
    });
    return _easeThemeManager;
}

+ (instancetype)sharedInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _easeThemeManager = [ETManager new];
    });
    return _easeThemeManager;
}

- (instancetype)init{
    if (self=[super init]) {
        self.weakArray = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory];
    }
    return self;
}

+ (NSString *)et_getSourceFilePathWithName:(NSString *)themeName {
    NSString *filePath = [[NSBundle mainBundle] pathForResource:themeName ofType:kETFileExtensionJSON];
    if (!ISValidString(filePath)) {
        filePath = [[NSBundle mainBundle] pathForResource:themeName ofType:kETFileExtensionPLIST];
    }
    return filePath;
}

+ (void)saveCurrentThemeInfosWithName:(NSString *)themeName type:(NSUInteger)themeType {
    _currentThemeName = themeName;
    _currentThemeType = themeType;
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:themeName forKey:kETCurrentThemeName];
    [userDefaults setObject:@(themeType) forKey:kETCurrentThemeType];
    [userDefaults synchronize];
}

+ (NSUInteger)getCurrentThemeType {
    if (_currentThemeType) return _currentThemeType;
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    _currentThemeType = [[userDefaults objectForKey:kETCurrentThemeType] integerValue];
    return _currentThemeType;
}

+ (NSString *)getCurrentThemeName {
    if (_currentThemeName) return _currentThemeName;
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    _currentThemeName = [userDefaults objectForKey:kETCurrentThemeName];
    if (!ISValidString(_currentThemeName)) {
        _currentThemeName = kETThemeNameDefault;
        [userDefaults setObject:kETThemeNameDefault forKey:kETCurrentThemeName];
        [userDefaults synchronize];
    }
    return _currentThemeName;
}

+ (BOOL)shiftThemeName:(NSString *)themeName {
    if (ISValidString(themeName)&&[themeName isEqualToString:_currentThemeName]) return NO;
    if (!ISValidString(themeName)) themeName = kETThemeNameDefault;
    _currentThemeName = themeName;
    _resourcesPath = [self et_getSourceFilePathWithName:themeName];
    
    if (ISValidString(_resourcesPath)) {
        NSUInteger currentThemeType = 0;//默认为0
        _themeDic = nil;
        [self saveCurrentThemeInfosWithName:themeName type:currentThemeType];
        for (EaseTheme *easeTheme in [ETManager sharedInstance].weakArray) {
            [easeTheme updateThemes];
        }
        return YES;
    }
    return NO;
}

- (void)addThemer:(id)themer {
    [self.weakArray addObject:themer];
}

#pragma mark - fetch resource

+ (NSDictionary *)getEaseThemeConfigFileData {
    if (_themeDic) {
        return _themeDic;
    }
    if (!ISValidString(_resourcesPath)) {
        NSString *currentThemeName = [self getCurrentThemeName];
        _resourcesPath = [self et_getSourceFilePathWithName:currentThemeName];
        NSData *data = [NSData dataWithContentsOfFile:_resourcesPath];
        if (!data) return nil;
        _themeDic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    }else{
        NSData *data = [NSData dataWithContentsOfFile:_resourcesPath];
        if (!data) return nil;
        _themeDic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    }
    if (!_themeDic||![_themeDic isKindOfClass:[NSDictionary class]]) return nil;
    return _themeDic;
}

@end

@implementation ETManager (ETSerialization)

+ (NSDictionary *)et_getObjVectorOperationKV {
    return @{
             kETArgColor : @"et_colorWithPath:",
             kETArgCGColor : @"et_cgColorWithPath:",
             kETArgImage : @"et_imageWithPath:",
             kETArgFont : @"et_fontWithPath",
             kETArgTextAttributes : @"et_titleTextAttributesDictionaryWithPath:",
             kETArgTitle : @"et_stringWithPath:",
             };
}

+ (NSDictionary *)et_getIntVectorOperationKV {
    return @{
             kETArgBarStyle : @"et_barStyleWithPath:",
             kETArgStatusBarStyle : @"et_statusBarStyleWithPath:",
             kETArgActivityIndicatorViewStyle : @"et_activityIndicatorStyleWithPath:",
             kETArgBool : @"et_boolWithPath:",
             };
}

+ (NSDictionary *)et_getFloatVectorOperationKV {
    return @{
             kETArgFloat : @"et_floatWithPath:",
             };
}

+ (UIColor *)et_colorWithPath:(NSString *)path {
    NSString *colorHexStr = [[self getEaseThemeConfigFileData] valueForKeyPath:path];
    if (!ISValidString(colorHexStr)) return nil;
    return [self et_colorFromString:colorHexStr];
}

+ (CGColorRef)et_cgColorWithPath:(NSString *)path {
    UIColor *rgbColor = [self et_colorWithPath:path];
    return rgbColor.CGColor;
}

+ (CGFloat)et_floatWithPath:(NSString *)path {
    NSString *valueStr = [[self getEaseThemeConfigFileData] valueForKeyPath:path];
    return [valueStr floatValue];
}

+ (BOOL)et_boolWithPath:(NSString *)path {
    return [[[self getEaseThemeConfigFileData] valueForKeyPath:path] boolValue];
}

+ (NSInteger)et_integerWithPath:(NSString *)path {
    return [[[self getEaseThemeConfigFileData] valueForKeyPath:path] integerValue];
}

+ (NSString *)et_stringWithPath:(NSString *)path {
    return [[self getEaseThemeConfigFileData] valueForKeyPath:path];
}

+ (UIImage *)et_imageWithPath:(NSString *)path {
    NSString *imageName = [self et_stringWithPath:path];
    UIImage *image = nil;
    if (ISValidString(imageName)) {
        if (_currentThemeType == ETThemeSourceType_bundle) {
            image = [UIImage imageNamed:imageName];
        } else if (_currentThemeType == ETThemeSourceType_sandbox) {
            image = [self _getImagePathWithImagename:imageName fileType:kETImageExtensionPNG];
            if (!image) {
                image = [self _getImagePathWithImagename:imageName fileType:kETImageExtensionJPG];
            }
        }
    }
    if (image) return image;
    return [self _searchImageWithPath:path];
}

+ (UIFont *)et_fontWithPath:(NSString *)path {
    CGFloat fontSize = [self et_floatWithPath:path];
    if (!fontSize) return nil;
    return [UIFont systemFontOfSize:fontSize];
}

+ (NSDictionary *)et_origDictionaryWithPath:(NSString *)path {
    return [[self getEaseThemeConfigFileData] valueForKeyPath:path];
}

+ (NSDictionary *)et_titleTextAttributesDictionaryWithPath:(NSString *)path {
    NSDictionary *origDict = [self et_origDictionaryWithPath:path];
    NSMutableDictionary *factDict = [NSMutableDictionary dictionaryWithCapacity:0];
    [origDict enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([key isEqualToString:@"NSForgroundColorAttributeName"]) {
            UIColor *color = [self et_colorFromString:(NSString *)obj];
            [factDict setObject:color forKey:NSForegroundColorAttributeName];
        }else if ([key isEqualToString:@"NSFontAttributeName"]) {
            CGFloat fontValue = [obj floatValue];
            UIFont *font = [UIFont systemFontOfSize:fontValue];
            [factDict setObject:font forKey:NSFontAttributeName];
        }else {}
    }];
    return factDict;
}

+ (UIStatusBarStyle)et_statusBarStyleWithPath:(NSString *)path {
    NSString *statusStr = [self et_stringWithPath:path];
    if ([statusStr isKindOfClass:[NSNumber class]]) {
        return [self _enumValueWith:(NSNumber *)statusStr];
    }
    if (![statusStr isKindOfClass:[NSString class]]) return UIStatusBarStyleDefault;
    
    if ([statusStr isEqualToString:@"UIStatusBarStyleLightContent"]) {
        return UIStatusBarStyleLightContent;
    }else{
        return UIStatusBarStyleDefault;
    }
}

+ (UIBarStyle)et_barStyleWithPath:(NSString *)path {
    NSString *barStyle = [self et_stringWithPath:path];
    if ([barStyle isKindOfClass:[NSNumber class]]) {
        return [self _enumValueWith:(NSNumber *)barStyle];
    }
    if (![barStyle isKindOfClass:[NSString class]]) return UIBarStyleDefault;
    
    if ([barStyle isEqualToString:@"UIBarStyleBlack"]) {
        return UIBarStyleBlack;
    }else {
        return UIBarStyleDefault;
    }
}

+ (UIKeyboardAppearance)et_keyboardAppearanceWithPath:(NSString *)path {
    NSString *kbAppearance = [self et_stringWithPath:path];
    
    if ([kbAppearance isKindOfClass:[NSNumber class]]) {
        return [self _enumValueWith:(NSNumber *)kbAppearance];
    }
    if (![kbAppearance isKindOfClass:[NSString class]]) return UIKeyboardAppearanceDefault;
    
    if ([kbAppearance isEqualToString:@"UIKeyboardAppearanceLight"]) {
        return UIKeyboardAppearanceLight;
    }else if ([kbAppearance isEqualToString:@"UIKeyboardAppearanceDark"]) {
        return UIKeyboardAppearanceDark;
    }else {
        return UIKeyboardAppearanceDefault;
    }
}

+ (UIActivityIndicatorViewStyle)et_activityIndicatorStyleWithPath:(NSString *)path {
    NSString *activityIndicatorStyle = [self et_stringWithPath:path];
    
    if ([activityIndicatorStyle isKindOfClass:[NSNumber class]]) {
        return [self _enumValueWith:(NSNumber *)activityIndicatorStyle];
    }
    if (![activityIndicatorStyle isKindOfClass:[NSString class]]) return UIActivityIndicatorViewStyleWhite;
    
    if ([activityIndicatorStyle isEqualToString:@"UIActivityIndicatorViewStyleWhiteLarge"]) {
        return UIActivityIndicatorViewStyleWhiteLarge;
    }else if ([activityIndicatorStyle isEqualToString:@"UIActivityIndicatorViewStyleGray"]) {
        return UIActivityIndicatorViewStyleGray;
    }else {
        return UIActivityIndicatorViewStyleWhite;
    }
}


#pragma mark - Private

+ (NSUInteger)_enumValueWith:(NSNumber *)number {
    return [number unsignedIntegerValue];
}

+ (UIImage *)_getImagePathWithImagename:(NSString *)imagename fileType:(NSString *)fileType {
    NSString *imagePath = [_resourcesPath stringByAppendingPathComponent:[imagename stringByAppendingPathComponent:fileType]];
    UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
    NSLog(@"image:%@ imagename:%@ filetype:%@",image,imagename,fileType);
    return image;
}

+ (UIImage *)_searchImageWithPath:(NSString *)path {
    NSArray *components = [path componentsSeparatedByString:@"."];
    NSString *component = [components lastObject];
    
    if ((component && [component isEqualToString:kETImageExtensionPNG])||(component && [component isEqualToString:kETImageExtensionJPG])) {
        component = path;
    }
    
    if (component) {
        UIImage *localImage = [UIImage imageNamed:component];
        return localImage;
    }
    return nil;
}

@end

@implementation ETManager (ETTool)

+ (UIColor *)et_colorFromString:(NSString *)hexStr {
    hexStr = [hexStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([hexStr hasPrefix:@"0x"]) {
        hexStr = [hexStr substringFromIndex:2];
    }
    if ([hexStr hasPrefix:@"#"]) {
        hexStr = [hexStr substringFromIndex:1];
    }
    
    NSUInteger hex = [self _intFromHexString:hexStr];
    if (hexStr.length>6) {
        return ETRGBHex(hex);
    }
    return ETRGBHex(hex);
}

+ (NSUInteger)_intFromHexString:(NSString *)hexStr {
    unsigned int hexInt = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexStr];
    [scanner scanHexInt:&hexInt];
    return hexInt;
}

@end

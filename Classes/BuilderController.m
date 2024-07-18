//
//  BuilderController.m
//  BetaBuilder
//
//  Created by Hunter Hillegas on 8/7/10.
//  Copyright 2010 Hunter Hillegas. All rights reserved.
//

/*
 iOS BetaBuilder - a tool for simpler iOS betas
 Version 1.6
 
 Condition of use and distribution:
 
 This software is provided 'as-is', without any express or implied
 warranty.  In no event will the authors be held liable for any damages
 arising from the use of this software.
 
 Permission is granted to anyone to use this software for any purpose,
 including commercial applications, and to alter it and redistribute it
 freely, subject to the following restrictions:
 
 1. The origin of this software must not be misrepresented; you must not
 claim that you wrote the original software. If you use this software
 in a product, an acknowledgment in the product documentation would be
 appreciated but is not required.
 2. Altered source versions must be plainly marked as such, and must not be
 misrepresented as being the original software.
 3. This notice may not be removed or altered from any source distribution.
 */

#import "NSFileManager+DirectoryLocations.h"
#import "BuilderController.h"
#import "ZipArchive.h"
#import "NSObject+DeepMutableCopy.h"
#import <CommonCrypto/CommonDigest.h> // Need to import for CC_MD5 access


#define JSON_OBJECT_WITH_STRING(string) (string?[NSJSONSerialization JSONObjectWithData: [string dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:nil]:nil)
#define JSON_STRING_WITH_OBJ(obj) (obj?[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:obj options:kNilOptions error:nil] encoding:NSUTF8StringEncoding]:nil)


@implementation NSString (MyAdditions)
- (NSString *)md5
{
    const char *cStr = [self UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, strlen(cStr), result ); // This is the md5 call
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}
@end

@implementation NSData (MyAdditions)
- (NSString*)md5
{
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5( self.bytes, self.length, result ); // This is the md5 call
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}
@end

@interface BuilderController()

@property (nonatomic) IBOutlet NSTextField *bundleIdentifierField;
@property (nonatomic) IBOutlet NSTextField *bundleVersionField;
@property (nonatomic) IBOutlet NSTextField *bundleNameField;
@property (nonatomic) IBOutlet NSTextField *webserverDirectoryField;
@property (nonatomic) IBOutlet NSTextField *archiveIPAFilenameField;
@property (nonatomic) IBOutlet NSButton *overwriteFilesButton;
@property (nonatomic) IBOutlet NSButton *includeZipFileButton;
@property (nonatomic) IBOutlet NSButton *generateFilesButton;
@property (nonatomic) IBOutlet NSButton *openInFinderButton;
@property (nonatomic) IBOutlet NSProgressIndicator *progressIndicator;

@property (nonatomic, copy) NSString *mobileProvisionFilePath;
@property (nonatomic, copy) NSString *appIconFilePath;
@property (nonatomic, copy) NSURL *destinationPath;
@property (nonatomic, copy) NSString *previousDestinationPathAsString;

@property (nonatomic, strong) NSString *folderName;
@property (nonatomic, strong) NSString *sourceIpaFilename;
@property (nonatomic, strong) NSString *manifest;
@property (nonatomic, strong) NSDictionary *bundlePlistFile;
@property (nonatomic, strong) NSString *artworkDestinationFilename;
@property (nonatomic, strong) NSDictionary *mobileProvision;
@property (nonatomic, strong) NSMutableArray *certificates;
@property (nonatomic, strong) NSMutableArray *devices;
@property (nonatomic, strong) NSString *modeString;
@property (nonatomic, strong) NSString *workspace;

- (BOOL)saveFilesToOutputDirectory:(NSURL *)saveDirectoryURL forManifestDictionary:(NSDictionary *)outerManifestDictionary withTemplateHTML:(NSString *)htmlTemplateString;
- (void)populateFieldsFromHistoryForBundleID:(NSString *)bundleID;
- (void)storeFieldsInHistoryForBundleID:(NSString *)bundleID;

@end

@implementation BuilderController

- (IBAction)specifyIPAFile:(id)sender {
    NSArray *allowedFileTypes = [NSArray arrayWithObjects:@"ipa", @"IPA", nil]; //only allow IPAs
    
    NSOpenPanel *openDlg = [NSOpenPanel openPanel];
    [openDlg setCanChooseFiles:YES];
    [openDlg setCanChooseDirectories:NO];
    [openDlg setAllowsMultipleSelection:NO];
    [openDlg setAllowedFileTypes:allowedFileTypes];
    
    if ([openDlg runModal] == NSOKButton) {
        NSArray *files = [openDlg URLs];
        
        for (int i = 0; i < [files count]; i++ ) {
            NSURL *fileURL = [files objectAtIndex:i];
            [self setupFromIPAFile:[fileURL path] workspace:nil];
        }
    }
}

- (void)setupFromIPAFile:(NSString *)ipaFilename workspace:(NSString *)workspace {
    self.sourceIpaFilename = ipaFilename;
    self.manifest = [[ipaFilename.lastPathComponent stringByDeletingPathExtension]stringByAppendingPathExtension:@"plist"];
    self.workspace = workspace;
    
    [self.archiveIPAFilenameField setStringValue:ipaFilename];
    
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *ipaSourceURL = [NSURL fileURLWithPath:[self.archiveIPAFilenameField stringValue]];
    if (![fileManager fileExistsAtPath:ipaSourceURL.path]) {
        NSLog(@"File not exists %@", ipaSourceURL);
        return;
    }
    
    NSString *uudiStr = [[NSUUID UUID]UUIDString];
    NSString *tempFolder = [NSTemporaryDirectory() stringByAppendingPathComponent:uudiStr];
    [fileManager removeItemAtPath:tempFolder error:nil];
    NSLog(@"Temp folder is %@", tempFolder);
    ZipArchive *za = [[ZipArchive alloc] init];
    if ([za UnzipOpenFile:[ipaSourceURL path]]) {
        BOOL ret = [za UnzipFileTo:tempFolder overWrite:YES];
        if (NO == ret){} [za UnzipCloseFile];
    }
    
    //read the Info.plist file
    NSString *appDirectoryPath = [tempFolder stringByAppendingPathComponent:@"Payload"];
    NSArray *payloadContents = [fileManager contentsOfDirectoryAtPath:appDirectoryPath error:nil];
    if ([payloadContents count] > 0) {
        NSString *plistPath = [[payloadContents objectAtIndex:0] stringByAppendingPathComponent:@"Info.plist"];
        self.bundlePlistFile = [NSDictionary dictionaryWithContentsOfFile:[appDirectoryPath stringByAppendingPathComponent:plistPath]];
        
        if (self.bundlePlistFile) {
            if ([self.bundlePlistFile valueForKey:@"CFBundleShortVersionString"]) {
                [self.bundleVersionField setStringValue:[NSString stringWithFormat:@"%@ (%@)", [self.bundlePlistFile valueForKey:@"CFBundleShortVersionString"], [self.bundlePlistFile valueForKey:@"CFBundleVersion"]]];
            } else {
                [self.bundleVersionField setStringValue:[self.bundlePlistFile valueForKey:@"CFBundleVersion"]];
            }
            
            [self.bundleIdentifierField setStringValue:[self.bundlePlistFile valueForKey:@"CFBundleIdentifier"]];
            
            if ([self.bundlePlistFile valueForKey:@"CFBundleDisplayName"]) {
                [self.bundleNameField setStringValue:[self.bundlePlistFile valueForKey:@"CFBundleDisplayName"]];
            } else {
                [self.bundleNameField setStringValue:@""];
            }
            
            [self.webserverDirectoryField setStringValue:@""];
            [self populateFieldsFromHistoryForBundleID:[self.bundlePlistFile valueForKey:@"CFBundleIdentifier"]];
            
            if ([self.bundlePlistFile valueForKey:@"MinimumOSVersion"]) {
                CGFloat minimumOSVerson = [[self.bundlePlistFile valueForKey:@"MinimumOSVersion"] floatValue];
                
                if (minimumOSVerson < 4.0) {
                    [self.includeZipFileButton setState:NSOnState];
                } else {
                    [self.includeZipFileButton setState:NSOffState];
                }
            }
            
            self.manifest = [[self filenameWithVersionString:ipaFilename] stringByAppendingPathExtension:@"plist"];
        }
        
        NSString *payloadPath = [appDirectoryPath stringByAppendingPathComponent:[payloadContents objectAtIndex:0]];
        //set mobile provision file
        self.mobileProvisionFilePath = [payloadPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
        [self loadMobileProvision];
        
        //set the app file icon path
        self.appIconFilePath = [payloadPath stringByAppendingPathComponent:@"iTunesArtwork"];
        //iTunesArtwork file does not exist - look for AppIcon60x60@2x.png instead
        if (![fileManager fileExistsAtPath:self.appIconFilePath]) {
            self.appIconFilePath = [payloadPath stringByAppendingPathComponent:@"AppIcon60x60@2x.png"];
        }
        //iTunesArtwork file does not exist - look for AppIcon57x57@2x.png instead
       if (![fileManager fileExistsAtPath:self.appIconFilePath]) {
            self.appIconFilePath = [payloadPath stringByAppendingPathComponent:@"AppIcon57x57@2x.png"];
        }
        
        // Now search All AppIcon*.png
        if (![fileManager fileExistsAtPath:self.appIconFilePath]) {
            NSArray *dirContents = [[fileManager contentsOfDirectoryAtPath:payloadPath error:nil] sortedArrayUsingSelector:@selector(compare:)];
            NSPredicate *fltr = [NSPredicate predicateWithFormat:@"self ENDSWITH[c] '.png' && self BEGINSWITH[c] 'AppIcon'"];
            NSArray *possibleIcons = [dirContents filteredArrayUsingPredicate:fltr];
            NSLog(@"Using possibleIcons %@", possibleIcons);
            if (possibleIcons.count) {
                self.appIconFilePath = [payloadPath stringByAppendingPathComponent:possibleIcons.firstObject];
            }
        }
        
    }
    
    [self.generateFilesButton setEnabled:YES];
    
    if (self.saveToDefaultFolder && self.bundlePlistFile) {
        NSString *bundleId = [self.bundlePlistFile valueForKey:@"CFBundleIdentifier"];
        self.folderName = [[NSString stringWithFormat:@"folder_of_%@", bundleId] md5];
        if (self.uploadToAppStore) {
            [self generateFilesWithWebserverAddress:[@"https://MYHOST/store/" stringByAppendingString:self.folderName]
                                 andOutputDirectory:[[NSString stringWithFormat:@"/Users/%@/Sites/store/", LOGGER_TARGET] stringByAppendingString:self.folderName]];
        } else {
            [self generateFilesWithWebserverAddress:[@"https://MYHOST/ipas/" stringByAppendingString:self.folderName]
                             andOutputDirectory:[[NSString stringWithFormat:@"/Users/%@/Sites/ipas/", LOGGER_TARGET] stringByAppendingString:self.folderName]];
        }
    }
    [fileManager removeItemAtPath:tempFolder error:nil];
}


- (NSDate *)dateFromString:(NSString *)dateString {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"YYYY-MM-dd'T'HH:mm:ssZZZ"];
    return [dateFormatter dateFromString:dateString];
}

- (NSString *)stringFromDate:(NSDate *)date {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"YYYY-MM-dd'T'HH:mm:ssZZZ"];
    return [dateFormatter stringFromDate:date];
}


-(NSDictionary*) loadMobileProvision {
    static NSDictionary* mobileProvision = nil;
    if (!mobileProvision) {
        if (![[NSFileManager defaultManager]fileExistsAtPath:self.mobileProvisionFilePath]) {
            NSLog(@"Mobile Provision File not exists %@", self.mobileProvisionFilePath);
            return nil;
        }
        // NSISOLatin1 keeps the binary wrapper from being parsed as unicode and dropped as invalid
        NSString *binaryString = [NSString stringWithContentsOfFile:self.mobileProvisionFilePath
                                                           encoding:NSISOLatin1StringEncoding
                                                              error:NULL];
        if (!binaryString) {
            return nil;
        }
        NSScanner *scanner = [NSScanner scannerWithString:binaryString];
        BOOL ok = [scanner scanUpToString:@"<plist" intoString:nil];
        if (!ok) {
            NSLog(@"unable to find beginning of plist");
            return nil;
        }
        
        NSString *plistString;
        ok = [scanner scanUpToString:@"</plist>" intoString:&plistString];
        if (!ok) {
            NSLog(@"unable to find end of plist");
            return nil;
        }
        
        plistString = [NSString stringWithFormat:@"%@</plist>",plistString];
// juggle latin1 back to utf-8!
        NSData *plistdata_latin1 = [plistString dataUsingEncoding:NSISOLatin1StringEncoding];
//		plistString = [NSString stringWithUTF8String:[plistdata_latin1 bytes]];
//		NSData *plistdata2_latin1 = [plistString dataUsingEncoding:NSISOLatin1StringEncoding];
        NSError *error = nil;
        mobileProvision = [NSPropertyListSerialization propertyListWithData:plistdata_latin1 options:NSPropertyListImmutable format:NULL error:&error];
        if (error) {
            NSLog(@"error parsing extracted plist — %@",error);
            if (mobileProvision) {
                mobileProvision = nil;
            }
            return nil;
        }
    }
    
    self.modeString = [self provisionModeString:[self provisionMode: mobileProvision]];

    NSMutableDictionary *mdict = [mobileProvision deepMutableCopy];
    
    NSArray *certs = mobileProvision[@"DeveloperCertificates"];
    self.certificates = [[NSMutableArray alloc]init];
    for (NSData *data in certs) {
        NSString *base64 = [data base64EncodedStringWithOptions:kNilOptions];
        NSString *subject = [self getSubject:base64];
        [self.certificates addObject: subject ?: @""];
    }
    [mdict removeObjectForKey: @"DeveloperCertificates"];

    NSArray *devices = mobileProvision[@"ProvisionedDevices"];
    self.devices = [[NSMutableArray alloc]init];
    for (NSString *uuid in devices) {
        [self.devices addObject: uuid];
    }
    [mdict removeObjectForKey: @"ProvisionedDevices"];
    
    // change date to string
    mdict[@"CreationDate"] = [self stringFromDate: mobileProvision[@"CreationDate"]];
    mdict[@"ExpirationDate"] = [self stringFromDate: mobileProvision[@"ExpirationDate"]];
    
    self.mobileProvision = mdict;
    return mobileProvision;
}

- (NSString *)getSubject: (NSString *)certBase64String {
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/sh"];
    
//    NSArray *arguments;
//    NSString *shellPath = [[NSBundle mainBundle]pathForResource:@"subject" ofType:@"sh"];
//    arguments = [NSArray arrayWithObjects: shellPath, certBase64String, nil];
//    [task setArguments: arguments];
    
    NSArray *arguments = [NSArray arrayWithObjects:
                          @"-c" ,
                          [NSString stringWithFormat:@"echo %@  | base64 -D | openssl x509 -subject -inform der | head -n 1", certBase64String],
                          nil];
    [task setArguments: arguments];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [task launch];
    NSData *data = [file readDataToEndOfFile];
    NSString *result = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    
//    return [NSString stringWithCString:[result cStringUsingEncoding:NSUTF8StringEncoding]
//                              encoding:NSNonLossyASCIIStringEncoding];
    
    return result;
}



-(UIApplicationReleaseMode) provisionMode: (NSDictionary *)mobileProvision {

    if (!mobileProvision) {
        // failure to read other than it simply not existing
        return UIApplicationReleaseUnknown;
    } else if (![mobileProvision count]) {
        return UIApplicationReleaseUnknown;
    } else if ([[mobileProvision objectForKey:@"ProvisionsAllDevices"] boolValue]) {
        // enterprise distribution contains ProvisionsAllDevices - true
        return UIApplicationReleaseEnterprise;
    } else if ([mobileProvision objectForKey:@"ProvisionedDevices"] && [[mobileProvision objectForKey:@"ProvisionedDevices"] count] > 0) {
        // development contains UDIDs and get-task-allow is true
        // ad hoc contains UDIDs and get-task-allow is false
        NSDictionary *entitlements = [mobileProvision objectForKey:@"Entitlements"];
        if ([[entitlements objectForKey:@"get-task-allow"] boolValue]) {
            return UIApplicationReleaseDev;
        } else {
            return UIApplicationReleaseAdHoc;
        }
    } else {
        // app store contains no UDIDs (if the file exists at all?)
        return UIApplicationReleaseAppStore;
    }
}

- (NSString *)provisionModeString: (UIApplicationReleaseMode) mode {
    switch (mode) {
        case UIApplicationReleaseUnknown:
            return @"未知";
            break;
        case UIApplicationReleaseSim:
            return @"模拟器";
            break;
        case UIApplicationReleaseDev:
            return @"开发版";
            break;
        case UIApplicationReleaseAdHoc:
            return @"内测版";
            break;
        case UIApplicationReleaseAppStore:
            return @"商店版";
            break;
        case UIApplicationReleaseEnterprise:
            return @"企业版";
            break;
            
        default:
            return @"未知";
            break;
    }
}

- (void)populateFieldsFromHistoryForBundleID:(NSString *)bundleID {
    NSString *applicationSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *historyPath = [applicationSupportPath stringByAppendingPathComponent:@"history.plist"];
    
    NSDictionary *historyDictionary = [NSDictionary dictionaryWithContentsOfFile:historyPath];
    
    if (historyDictionary) {
        NSDictionary *historyItem = [historyDictionary valueForKey:bundleID];
        if (historyItem) {
            [self.webserverDirectoryField setStringValue:[historyItem valueForKey:@"webserverDirectory"]];
        } else {
            NSLog(@"No History Item Found for Bundle ID: %@", bundleID);
        }
        
        NSDictionary *outputPathItem = [historyDictionary valueForKey:[NSString stringWithFormat:@"%@-output", bundleID]];
        if (outputPathItem) {
            self.previousDestinationPathAsString = [outputPathItem valueForKey:@"outputDirectory"];
        } else {
            NSLog(@"No Output Path History Item Found for Bundle ID: %@", bundleID);
        }
    }
}

- (void)storeFieldsInHistoryForBundleID:(NSString *)bundleID {
    NSString *applicationSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *historyPath = [applicationSupportPath stringByAppendingPathComponent:@"history.plist"];
    NSString *trimmedURLString = [[self.webserverDirectoryField stringValue] stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSString *outputDirectoryPath = [self.destinationPath path];
    
    NSMutableDictionary *historyDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:historyPath];
    if (!historyDictionary) {
        historyDictionary = [NSMutableDictionary dictionary];
    }
    
    NSDictionary *webserverDirectoryDictionary = [NSDictionary dictionaryWithObjectsAndKeys:trimmedURLString, @"webserverDirectory", nil];
    [historyDictionary setValue:webserverDirectoryDictionary forKey:bundleID];
    
    NSDictionary *outputDirectoryDictionary = [NSDictionary dictionaryWithObjectsAndKeys:outputDirectoryPath, @"outputDirectory", nil];
    [historyDictionary setValue:outputDirectoryDictionary forKey:[NSString stringWithFormat:@"%@-output", bundleID]];
    
    [historyDictionary writeToFile:historyPath atomically:YES];
}

- (IBAction)generateFiles:(id)sender {
    [self generateFilesWithWebserverAddress:[self.webserverDirectoryField stringValue] andOutputDirectory:nil];
}

- (void)generateFilesWithWebserverAddress:(NSString *)webserver andOutputDirectory:(NSString *)outputPath {
    //create plist
    NSString *encodedWebserver = [webserver stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *trimmedURLString = [encodedWebserver stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSString *encodedIpaFilename = [[self filenameWithVersionString:[self.archiveIPAFilenameField stringValue]] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; //this isn't the most robust way to do this
    NSString *ipaURLString = [NSString stringWithFormat:@"%@/%@", trimmedURLString, encodedIpaFilename];
    NSDictionary *assetsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"software-package", @"kind", ipaURLString, @"url", nil];
    NSDictionary *metadataDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[self.bundleIdentifierField stringValue], @"bundle-identifier", [self.bundleVersionField stringValue], @"bundle-version", @"software", @"kind", [self.bundleNameField stringValue], @"title", nil];
    NSDictionary *innerManifestDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:assetsDictionary], @"assets", metadataDictionary, @"metadata", nil];
    NSDictionary *outerManifestDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:innerManifestDictionary], @"items", nil];
    
    //create html file
    NSString *applicationSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *templatePath = nil;
    
    if (_templateFile != nil) {
        if ([_templateFile hasPrefix:@"~"]) {
            _templateFile = [_templateFile stringByExpandingTildeInPath];
        }
        
        if ([_templateFile hasPrefix:@"/"]) {
            templatePath = _templateFile;
        } else  {
            templatePath = [applicationSupportPath stringByAppendingPathComponent:_templateFile];
        } if (![[NSFileManager defaultManager] fileExistsAtPath:templatePath]) {
            NSLog(@"Template file does not exist at path: %@", templatePath);
            exit(1);
        }
    } else  {
        if ([self.includeZipFileButton state] == NSOnState) {
            templatePath = [applicationSupportPath stringByAppendingPathComponent:@"index_template.html"];
        } else {
            templatePath = [applicationSupportPath stringByAppendingPathComponent:@"index_template_no_tether.html"];
        }
    }
    
    NSString *htmlTemplateString = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:nil];
    htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_NAME]" withString:[self.bundleNameField stringValue]];
    htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_VERSION]" withString:[self.bundleVersionField stringValue]];
    htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_PLIST]"
                                                                       withString:[NSString stringWithFormat:@"%@/%@", trimmedURLString, self.manifest]];
    
    //add formatted date
    NSDateFormatter *shortDateFormatter = [[NSDateFormatter alloc] init];
    [shortDateFormatter setTimeStyle:NSDateFormatterNoStyle];
    [shortDateFormatter setDateStyle:NSDateFormatterMediumStyle];
    NSString *formattedDateString = [shortDateFormatter stringFromDate:[NSDate date]];
    htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_DATE]" withString:formattedDateString];
    
    if (!outputPath) {
        //ask for save location
        NSOpenPanel *directoryPanel = [NSOpenPanel openPanel];
        [directoryPanel setCanChooseFiles:NO];
        [directoryPanel setCanChooseDirectories:YES];
        [directoryPanel setAllowsMultipleSelection:NO];
        [directoryPanel setCanCreateDirectories:YES];
        [directoryPanel setPrompt:@"Choose Directory"];
        [directoryPanel setMessage:@"Choose the Directory for Beta Files - Probably Should Match Deployment Directory and Should NOT Include the IPA"];
        
        if (self.previousDestinationPathAsString) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:self.previousDestinationPathAsString]) {
                NSLog(@"Previous Directory Exists - Using That");
                
                [directoryPanel setDirectoryURL:[NSURL fileURLWithPath:self.previousDestinationPathAsString]];
            }
        }
        
        if ([directoryPanel runModal] == NSOKButton) {
            NSURL *saveDirectoryURL = [directoryPanel directoryURL];
            BOOL saved = [self saveFilesToOutputDirectory:saveDirectoryURL forManifestDictionary:outerManifestDictionary withTemplateHTML:htmlTemplateString];
            
            if (saved) {
                self.destinationPath = saveDirectoryURL;
                
                NSSound *systemSound = [NSSound soundNamed:@"Glass"]; //Play Done Sound / Display Alert
                [systemSound play];
                
                //store history
                if (trimmedURLString)
                    [self storeFieldsInHistoryForBundleID:[self.bundleIdentifierField stringValue]];
                
                //show in finder
                [self.openInFinderButton setEnabled:YES];
                
                //put the doc in recent items
                [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:[self.archiveIPAFilenameField stringValue]]];
            } else {
                NSBeep();
            }
        }
    } else {
        NSURL *saveDirectoryURL = [NSURL fileURLWithPath:outputPath];
        BOOL saved = [self saveFilesToOutputDirectory:saveDirectoryURL forManifestDictionary:outerManifestDictionary withTemplateHTML:htmlTemplateString];
        NSString *displayName = [self.bundlePlistFile valueForKey:@"CFBundleDisplayName"];
        if (saved && self.saveToDefaultFolder) {
            if (self.artworkDestinationFilename && self.folderName && self.sourceIpaFilename && self.manifest && displayName) {
                NSError *error = nil;
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1/ipas/ipa_uploaded.php"]];
                NSDictionary *dict = @{
                                       @"devices" : self.devices ? JSON_STRING_WITH_OBJ(self.devices) : @"",
                                       @"certificates" : self.certificates ? JSON_STRING_WITH_OBJ(self.certificates) : @"",
                                       @"provision" : self.modeString,
                                       @"provisioncontents" : JSON_STRING_WITH_OBJ(self.mobileProvision) ?: @"",
                                       @"teamname" : [self.mobileProvision objectForKey:@"TeamName"] ?: @"",
                                       @"expirationtime" : [NSString stringWithFormat:@"%f", [[self dateFromString:[self.mobileProvision objectForKey:@"ExpirationDate"]] timeIntervalSince1970]],
                                       @"bundleid" : [self.bundlePlistFile valueForKey:@"CFBundleIdentifier"],
                                       @"folder" : self.folderName,
                                       @"displayname" : displayName,
                                       @"appversion" :  [self.bundlePlistFile valueForKey:@"CFBundleShortVersionString"],
                                       @"appbuild" : [self.bundlePlistFile valueForKey:@"CFBundleVersion"],
                                       @"ipafile" : [self filenameWithVersionString:self.sourceIpaFilename],
                                       @"manifest" : self.manifest,
                                       @"iconfile" : self.artworkDestinationFilename,
                                       @"workspace" : self.workspace ?: @"",
                                       @"store" : [NSNumber numberWithBool:self.uploadToAppStore]
                                       };
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:kNilOptions error:nil];
                NSLog(@"POSTING with \n%@", [[NSString alloc]initWithData:jsonData encoding:NSUTF8StringEncoding]);
                request.HTTPBody = jsonData;
                request.HTTPMethod = @"POST";
                NSData *resultData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:&error];
                NSLog(@"IPAINSTALLED result %@", [[NSString alloc]initWithData:resultData encoding:NSUTF8StringEncoding]);
                if (error) {
                    NSLog(@"Error %@", error);
                }
            } else {
                NSLog(@"=========== error =========== Icon:`%@` DisplayName:`%@` Folder:`%@` IPA:`%@` Manifest:`%@`", self.artworkDestinationFilename, displayName, self.folderName, self.sourceIpaFilename, self.manifest);
                exit(1);
            }
            
        }
    }
}

- (NSString *)filenameWithVersionString:(NSString *)ipaFullname {
    if (self.bundlePlistFile) {
        NSString *ipaFilenameWithoutExt = [ipaFullname.lastPathComponent stringByDeletingPathExtension];
        NSString *appVersion = [self.bundlePlistFile valueForKey:@"CFBundleShortVersionString"];
        NSString *appBuild = [self.bundlePlistFile valueForKey:@"CFBundleVersion"];
        NSString *suffix = [NSString stringWithFormat:@"-%@-%@", appVersion, appBuild];
        if (![ipaFilenameWithoutExt hasSuffix:suffix]) {
            ipaFilenameWithoutExt = [ipaFilenameWithoutExt stringByAppendingString:suffix];
        }
        
        NSString *ipaFileExtension = ipaFullname.pathExtension;
        NSString *ipaFilename = [ipaFilenameWithoutExt stringByAppendingPathExtension:ipaFileExtension];
        return ipaFilename;
    } else {
        return [ipaFullname lastPathComponent];
    }
}

- (BOOL)saveFilesToOutputDirectory:(NSURL *)saveDirectoryURL forManifestDictionary:(NSDictionary *)outerManifestDictionary withTemplateHTML:(NSString *)htmlTemplateString {
    BOOL savedSuccessfully = NO;
    
    [self.progressIndicator startAnimation:nil];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtURL:saveDirectoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    
    //Copy or Move IPA
    NSError *fileCopyError;
    NSString *ipaFullname = [self.archiveIPAFilenameField stringValue];
    NSURL *ipaSourceURL = [NSURL fileURLWithPath:ipaFullname];
    NSString *ipaFilename = [self filenameWithVersionString:ipaFullname];
    NSURL *ipaDestinationURL = [saveDirectoryURL URLByAppendingPathComponent:ipaFilename];

    fileManager.delegate = self;
    BOOL copiedIPAFile;
    copiedIPAFile = [fileManager copyItemAtURL:ipaSourceURL toURL:ipaDestinationURL error:&fileCopyError];
    
    if (!copiedIPAFile) {
        NSLog(@"Error Saving IPA File: %@", fileCopyError);
        NSAlert *theAlert = [NSAlert alertWithError:fileCopyError];
        NSInteger button = [theAlert runModal];
        if (button != NSAlertFirstButtonReturn) {
            //user hit the rightmost button
        }
        
        return NO;
    } else {
        [fileManager setAttributes:@{ NSFilePosixPermissions : @0666 }
                      ofItemAtPath:ipaDestinationURL.path
                             error:nil];
    }
    
    //Copy README
    if ([self.includeZipFileButton state] == NSOnState) {
        if ([self.overwriteFilesButton state] == NSOnState)
            [fileManager removeItemAtURL:[saveDirectoryURL URLByAppendingPathComponent:@"README.txt"] error:nil];
        
        NSString *readmeContents = [[NSBundle mainBundle] pathForResource:@"README" ofType:@""];
        [readmeContents writeToURL:[saveDirectoryURL URLByAppendingPathComponent:@"README.txt"] atomically:YES encoding:NSASCIIStringEncoding error:nil];
    }
    
    //If iTunesArtwork file exists, use it
    BOOL doesArtworkExist = [fileManager fileExistsAtPath:self.appIconFilePath];
    if (doesArtworkExist) {
        self.artworkDestinationFilename = [NSString stringWithFormat:@"%@.png", [self.appIconFilePath lastPathComponent]];
        self.artworkDestinationFilename = [self.artworkDestinationFilename stringByReplacingOccurrencesOfString:@".png.png" withString:@".png"]; //fix for commonly incorrectly named files
        self.artworkDestinationFilename = [self.artworkDestinationFilename stringByReplacingOccurrencesOfString:@"@2x.png" withString:@".png"];
        self.artworkDestinationFilename = [self.artworkDestinationFilename stringByReplacingOccurrencesOfString:@".png"
                                                                                           withString:[NSString stringWithFormat:@"_%@_%@.png", [self.bundlePlistFile valueForKey:@"CFBundleShortVersionString"], [self.bundlePlistFile valueForKey:@"CFBundleVersion"]]];

        NSURL *artworkSourceURL = [NSURL fileURLWithPath:self.appIconFilePath];
        NSURL *artworkDestinationURL = [saveDirectoryURL URLByAppendingPathComponent:self.artworkDestinationFilename];
        NSString *convertResult = [self png_convert:artworkSourceURL.path to:artworkDestinationURL.path];
        NSLog(@"png_convert: %@ \nsaved to %@", convertResult, artworkDestinationURL.path);
        [fileManager setAttributes:@{ NSFilePosixPermissions : @0666 }
                      ofItemAtPath:artworkDestinationURL.path
                             error:nil];

        htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_ICON]" withString:[NSString stringWithFormat:@"<p><img src='%@' length='57' width='57' /></p>", self.artworkDestinationFilename]];
        
    } else {
        NSLog(@"No iTunesArtwork File Exists in Bundle");
        htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_ICON]" withString:@""];
    }
    
    //Write Files
    if ([self.overwriteFilesButton state] == NSOnState) {
        [fileManager removeItemAtURL:[saveDirectoryURL URLByAppendingPathComponent:self.manifest] error:nil];
    }
    
    NSError *fileWriteError;
    NSURL *manifestUrl = [saveDirectoryURL URLByAppendingPathComponent:self.manifest];
    [outerManifestDictionary writeToURL:manifestUrl atomically:YES];
    [fileManager setAttributes:@{ NSFilePosixPermissions : @0666 }
                  ofItemAtPath:manifestUrl.path
                         error:nil];
    NSLog(@"Manifest file saved to %@", manifestUrl);
    
    if (!self.saveToDefaultFolder) {
        BOOL wroteHTMLFileSuccessfully = [htmlTemplateString writeToURL:[saveDirectoryURL URLByAppendingPathComponent:@"index.html"]
                                                             atomically:YES
                                                               encoding:NSUTF8StringEncoding
                                                                  error:&fileWriteError];
        
        if (!wroteHTMLFileSuccessfully) {
            NSLog(@"Error Writing HTML File: %@ to %@", fileWriteError, saveDirectoryURL);
            savedSuccessfully = NO;
        } else {
            savedSuccessfully = YES;
        }
    } else {
        savedSuccessfully = YES;
    }
    
    
    //Create Archived Version for 3.0 Apps
    if ([self.includeZipFileButton state] == NSOnState) {
        ZipArchive *zip = [[ZipArchive alloc] init];
        
        [zip CreateZipFile2:[[saveDirectoryURL path] stringByAppendingPathComponent:@"beta_archive.zip"]];
        [zip addFileToZip:[self.archiveIPAFilenameField stringValue] newname:@"application.ipa"];
        [zip addFileToZip:self.mobileProvisionFilePath newname:@"beta_provision.mobileprovision"];
        
        if (![zip CloseZipFile2]) {
            NSLog(@"Error Creating 3.x Zip File");
        }
    }
    
    [self.progressIndicator stopAnimation:nil];
    
    return savedSuccessfully;
}

- (NSString *)png_convert: (NSString *)sourcePng to: (NSString *)destPng {
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/sh"];
    
    
    NSArray *arguments = [NSArray arrayWithObjects:
                          @"-c" ,
                          [NSString stringWithFormat:@"xcrun -sdk iphoneos pngcrush -revert-iphone-optimizations \"%@\" \"%@\"", sourcePng, destPng],
                          nil];
    [task setArguments: arguments];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [task launch];
    NSData *data = [file readDataToEndOfFile];
    NSString *result = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    return result;
}


- (BOOL)fileManager:(NSFileManager *)fileManager shouldCopyItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL {
    if ([srcURL isEqual:dstURL])
        return NO;
    
    if ([self.overwriteFilesButton state] == NSOnState) {
        if ([fileManager fileExistsAtPath:[dstURL path]]) {
            NSLog(@"Overwriting File: %@", dstURL);
            
            NSError *deleteError;
            BOOL deleted = [fileManager removeItemAtURL:dstURL error:&deleteError];
            
            if (!deleted) {
                NSLog(@"Error Deleting %@: %@", dstURL, deleteError);
            }
        } else {
            NSLog(@"File Didn't Exist to Delete: %@", dstURL);
        }
    }
    
    return YES;
}

- (IBAction)openInFinder:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:self.destinationPath];
}

@end

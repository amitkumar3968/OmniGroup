// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISyncListController.h"

#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/OFFileWrapper.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIReplaceDocumentAlert.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "OUICredentials.h"
#import "OUISyncDownloader.h"

// TODO: Refactor so neither OUIWebDAVConnection.h nor OUIWebDAVSetup.h need to be included here.
#import "OUIWebDAVConnection.h"
#import "OUIWebDAVSetup.h"

RCS_ID("$Id$");

@interface OUISyncListController (/* Private */)

- (NSString *)_formattedFileSize:(NSUInteger)sizeinBytes;
- (void)_updateNavigationButtons;
- (void)_fadeOutDownload:(OUISyncDownloader *)downloader;
- (void)_goBack:(id)sender;

@end


@implementation OUISyncListController

@synthesize syncType = _syncType;
@synthesize address = _address;
@synthesize connectingView = _connectingView;
@synthesize connectingProgress = _connectingProgress;
@synthesize connectingLabel = _connectingLabel;
@synthesize files = _files;
@synthesize isExporting = _isExporting;
@synthesize exportFileWrapper = _exportFileWrapper;

@synthesize downloader = _downloader;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [super initWithNibName:@"OUISyncListController" bundle:OMNI_BUNDLE];
}

- (void)dealloc;
{
    [_address release];
    [_files release];
    [_connectingView release];
    [_connectingProgress release];
    [_connectingLabel release];
    
    [_exportFileWrapper release];
    
    [_exportURL release];
    [_exportIndexPath release];
    [_downloader release];
    
    [super dealloc];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [self _updateNavigationButtons];
}

- (void)viewDidUnload;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_exportFileWrapper release];
    _exportFileWrapper = nil;
    
    [_exportURL release];
    _exportURL = nil;
    
    [_exportIndexPath release];
    _exportIndexPath = nil;
    
    [_connectingView release];
    _connectingView = nil;
    [_connectingProgress release];
    _connectingProgress = nil;
    [_connectingLabel release];
    _connectingLabel = nil;
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    self.navigationItem.titleView = _connectingView;
    [_connectingProgress startAnimating];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_loadFiles) name:OUICertificateTrustUpdated object:nil];
    [self performSelector:@selector(_loadFiles) withObject:nil afterDelay:0];
    
    _connectingLabel.text = NSLocalizedStringFromTableInBundle(@"Connecting", @"OmniUI", OMNI_BUNDLE, @"webdav connecting label");
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUICertificateTrustUpdated object:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    return YES;
}

#pragma mark -
#pragma mark API
- (void)export:(id)sender;
{
    // TODO: Must override in subclass.
}

- (void)signOut:(id)sender;
{
    OUIDeleteCredentialsForProtectionSpace([[[OUIWebDAVConnection sharedConnection] authenticationChallenge] protectionSpace]);
    [[OUIWebDAVConnection sharedConnection] close];
    
    switch (_syncType) {
        case OUIWebDAVSync:
            [[OFPreference preferenceForKey:OUIWebDAVLocation] restoreDefaultValue];
            [[OFPreference preferenceForKey:OUIWebDAVUsername] restoreDefaultValue];
            break;
        case OUIMobileMeSync:
        {
            [[OFPreference preferenceForKey:OUIMobileMeUsername] restoreDefaultValue];
            break;
        }
            
        case OUIOmniSync:
        {
            [[OFPreference preferenceForKey:OUIOmniSyncUsername] restoreDefaultValue];
            break;
        }
            
        default:
            break;
    }
    
    OUIWebDAVSetup *setupView = [[OUIWebDAVSetup alloc] init];
    [setupView setSyncType:_syncType];
    
    [self.navigationController dismissModalViewControllerAnimated:YES];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:setupView];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    OUIAppController *appController = [OUIAppController controller];
    [appController.topViewController presentModalViewController:navigationController animated:YES];
    
    [navigationController release];
    [setupView release];
}

- (void)cancel:(id)sender;
{
    [self.navigationController dismissModalViewControllerAnimated:YES];
    [[OUIWebDAVConnection sharedConnection] close];
}

- (void)setFiles:(NSArray *)newFiles;
{
    [_files release];
    _files = [newFiles retain];
    
    [(UITableView *)self.view reloadData];
}

- (void)downloadFinished:(NSNotification *)notification;
{
    OUISyncDownloader *downloader = [notification object];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISyncDownloadFinishedNotification object:downloader];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISyncDownloadCanceledNotification object:downloader];
    
    
    if (_isExporting) {
        _isExporting = NO;
        [self.navigationController performSelector:@selector(dismissModalViewControllerAnimated:) withObject:[NSNumber numberWithBool:YES] afterDelay:0.5];        
    } else if (_isDownloading) {
        [self _fadeOutDownload:downloader];
        [self.navigationController dismissModalViewControllerAnimated:YES];
        
        NSURL *downloadURL = [[notification userInfo] objectForKey:OUISyncDownloadURL];
        [[[OUIAppController controller] documentPicker] addDocumentFromURL:downloadURL];
        
        _isDownloading = NO;
    }
}

- (void)downloadCanceled:(NSNotification *)notification;
{
    OUISyncDownloader *downloader = [notification object];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISyncDownloadFinishedNotification object:downloader];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISyncDownloadCanceledNotification object:downloader];
    
    [self _fadeOutDownload:downloader];
    
    _isDownloading = NO;
    
    if (_isExporting) {
        [_files release];
        _files = nil;
        
        [self _loadFiles];
        [self _updateNavigationButtons];
    }
}

- (void)addDownloaderWithURL:(NSURL *)exportURL toCell:(UITableViewCell *)cell;
{
    // Should override in subclass.
}

- (void)_exportToNewPathGeneratedFromURL:(NSURL *)documentURL;
{
    // Should override in subclass.
}
#pragma mark -
#pragma mark OUIReplaceDocumentAlert
- (void)replaceDocumentAlert:(OUIReplaceDocumentAlert *)alert didDismissWithButtonIndex:(NSInteger)buttonIndex documentURL:(NSURL *)documentURL;
{
    [_replaceDocumentAlert release];
    _replaceDocumentAlert = nil;
    
    switch (buttonIndex) {
        case 0: /* Cancel */
            self.navigationItem.rightBarButtonItem.enabled = YES;
            break;
            
        case 1: /* Replace */
        {
            [self _exportToURL:documentURL];
            break;
        }
        case 2: /* Add */
        {
            [self _exportToNewPathGeneratedFromURL:documentURL];
            break;
        }
        default:
            break;
    }
}

#pragma mark -
#pragma mark Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    return [_files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier] autorelease];
    }
    
    OFSFileInfo *fileInfo = [_files objectAtIndex:indexPath.row];
    cell.textLabel.text = [[fileInfo name] stringByDeletingPathExtension];
    cell.accessoryType = (![self _canOpenFile:fileInfo] && [fileInfo isDirectory]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    
    BOOL canOpenFile = ([fileInfo isDirectory] || [self _canOpenFile:fileInfo] || _isExporting) && [fileInfo exists];
    cell.textLabel.textColor = canOpenFile ? [UIColor blackColor] : [UIColor grayColor];
    
    if (![fileInfo isDirectory] || [self _canOpenFile:fileInfo]) {
        NSDate *lastModifiedDate = [fileInfo lastModifiedDate];
        if (lastModifiedDate) {
            NSLog(@"%@", fileInfo.name);
            NSLog(@"%@", fileInfo.lastModifiedDate);
            
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateStyle:NSDateFormatterMediumStyle];
            [formatter setLocale:[NSLocale currentLocale]];
            cell.detailTextLabel.text = [formatter stringFromDate:lastModifiedDate];
            [formatter release];
        }
    }
    else {
        cell.detailTextLabel.text = nil;
    }
    
    UIImage *icon = nil;
    if ([self _canOpenFile:fileInfo]) {
        OUIDocumentPicker *picker = [[OUIAppController controller] documentPicker];
        icon = [picker iconForUTI:[fileInfo UTI]];
    } else if ([fileInfo isDirectory]) {
        icon = [UIImage imageNamed:@"OUIFolder.png"];
    } else {
        icon = [UIImage imageNamed:@"OUIDocument.png"];
    }
    
    cell.imageView.image = icon;
    
    return cell;
}


#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // TODO: This should be handled in the subclass.
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (_isDownloading)
        return nil;
    
    OFSFileInfo *fileInfo = [_files objectAtIndex:indexPath.row];
    if (![self _canOpenFile:fileInfo] && [fileInfo isDirectory])
        return indexPath;
    
    if (_isExporting)
        return nil;
    
    return [self _canOpenFile:fileInfo] ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (!_isExporting || indexPath.row != _exportIndexPath.row || _exportURL == nil)
        return;
    
    [self addDownloaderWithURL:_exportURL toCell:cell];
    
    [_exportURL release];
    _exportURL = nil;
    
    [_exportIndexPath release];
    _exportIndexPath = nil;
}

#pragma mark private
- (void)_displayDuplicateFileAlertForFile:(NSURL *)fileURL;
{
    OBASSERT(_replaceDocumentAlert == nil); // this should never happen
    _replaceDocumentAlert = [[OUIReplaceDocumentAlert alloc] initWithDelegate:self documentURL:fileURL];
    [_replaceDocumentAlert show];
}
- (BOOL)_canOpenFile:(OFSFileInfo *)fileInfo;
{
    return [[OUIAppController controller] canViewFileTypeWithIdentifier:[fileInfo UTI]];
}

- (void)_cancelDownloadEffectDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    OBASSERT([(id)context isKindOfClass:[UITableViewCell class]]);
    [(UITableViewCell *)context setAccessoryView:nil];
    
    [(UITableView *)self.view reloadData];
}

- (NSString *)_formattedFileSize:(NSUInteger)sizeinBytes;
{
    NSString *formattedString = nil;
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setMaximumFractionDigits:1];
    
    if (sizeinBytes < 1e3) {
        NSString *formattedNumber = [formatter stringFromNumber:[NSNumber numberWithFloat:sizeinBytes]];
        formattedString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ B", @"OmniUI", OMNI_BUNDLE, @"bytes"), formattedNumber];
    } else if (sizeinBytes < 1e6) {
        NSString *formattedNumber = [formatter stringFromNumber:[NSNumber numberWithFloat:sizeinBytes / 1e3]];
        formattedString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ KB", @"OmniUI", OMNI_BUNDLE, @"kilobytes"), formattedNumber];
    } else if (sizeinBytes < 1e9) {
        NSString *formattedNumber = [formatter stringFromNumber:[NSNumber numberWithFloat:sizeinBytes / 1e6]];
        formattedString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ MB", @"OmniUI", OMNI_BUNDLE, @"megabytes"), formattedNumber];
    } else {
        NSString *formattedNumber = [formatter stringFromNumber:[NSNumber numberWithFloat:sizeinBytes / 1e9]];
        formattedString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ GB", @"OmniUI", OMNI_BUNDLE, @"gigabytes"), formattedNumber];
    }
    
    [formatter release];
    return formattedString;
}

- (void)_loadFiles;
{
    if (_files) {
        [self _stopConnectingIndicator];
        return;
    }
    
    // This should be implemented in subclasses.
}

- (void)_updateNavigationButtons;
{
    NSString *syncButtonTitle = nil;
    UIBarButtonItem *syncBarButtonItem = nil;
    if (_isExporting) {
        syncButtonTitle = NSLocalizedStringFromTableInBundle(@"Export", @"OmniUI", OMNI_BUNDLE, @"export button title");
        syncBarButtonItem = [[OUIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleBordered target:self action:@selector(export:)];
    } else {
        syncButtonTitle = NSLocalizedStringFromTableInBundle(@"Sign Out", @"OmniUI", OMNI_BUNDLE, @"sign out button title");
        syncBarButtonItem = [[OUIBarButtonItem alloc] initWithTitle:syncButtonTitle style:UIBarButtonItemStyleBordered target:self action:@selector(signOut:)];
    }
    
    UINavigationItem *navigationItem = self.navigationItem;
    OBASSERT(navigationItem);
    
    navigationItem.rightBarButtonItem = syncBarButtonItem;
    [syncBarButtonItem release];
    
    UINavigationController *navigationController = self.navigationController;
    NSArray *viewControllers = navigationController.viewControllers;
    NSUInteger viewIndex = [viewControllers indexOfObjectIdenticalTo:self];
    
    if (viewIndex == 0) {
        UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
        navigationItem.leftBarButtonItem = cancel;
        [cancel release];
    }
    
#if 1
    // Custom view items get ignored for the back item. Also, unlike the 'back to me' button, the left button needs to reference the title of the previous view controller and it needs a real target/action
    if (viewIndex != 0) {
        UIViewController *previousController = [viewControllers objectAtIndex:viewIndex - 1];
        navigationItem.leftBarButtonItem = [[[OUIBarButtonItem alloc] initWithBackgroundType:OUIBarButtonItemBackgroundTypeBack image:nil title:previousController.navigationItem.title target:self action:@selector(_goBack:)] autorelease];
    }
#else
    // 'backBarButtonItem' is for 'go back to *me*'
    navigationItem.backBarButtonItem = [[[OUIBarButtonItem alloc] initWithBackgroundType:OUIBarButtonItemBackgroundTypeBack image:nil title:[NSString stringWithFormat:@"??? %@", self.title] target:nil action:NULL] autorelease];
    //navigationItem.backBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:self.title style:UIBarButtonItemStyleBordered target:nil action:NULL] autorelease];
#endif
}

- (void)_fadeOutDownload:(OUISyncDownloader *)downloader;
{
    for (UITableViewCell *cell in [(UITableView *)self.view visibleCells]) {
        if (cell.accessoryView == downloader.view) {
            
            [UIView beginAnimations:@"OUIWebDAVSyncListController_cancel_download" context:cell];
            {
                cell.accessoryView.alpha = 0;
                
                [UIView setAnimationDelegate:self];
                [UIView setAnimationDidStopSelector:@selector(_cancelDownloadEffectDidStop:finished:context:)];
            }
            [UIView commitAnimations];
            break;
        }
    }
}

- (void)_exportToURL:(NSURL *)exportURL;
{
    OFSFileInfo *emptyFile = [[OFSFileInfo alloc] initWithOriginalURL:exportURL name:[OFSFileInfo nameForURL:exportURL] exists:NO directory:NO size:0 lastModifiedDate:nil];
    NSMutableArray *newFiles = [NSMutableArray arrayWithObject:emptyFile];
    [emptyFile release];
    [newFiles addObjectsFromArray:_files];
    [newFiles sortUsingSelector:@selector(compareByName:)];
    [self setFiles:newFiles];
    
    NSIndexPath *indexPathToEmptyFile = [NSIndexPath indexPathForRow:[_files indexOfObject:emptyFile] inSection:0];
    if ([(UITableView *)self.view cellForRowAtIndexPath:indexPathToEmptyFile] != nil) {
        UITableViewCell *cell = [(UITableView *)self.view cellForRowAtIndexPath:indexPathToEmptyFile];
        [self addDownloaderWithURL:exportURL toCell:cell];
    } else {
        [_exportURL release];
        _exportURL = [exportURL retain];
        
        [_exportIndexPath release];
        _exportIndexPath = [indexPathToEmptyFile retain];
        
        [(UITableView *)self.view scrollToRowAtIndexPath:_exportIndexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
    }
}

- (void)_stopConnectingIndicator;
{
    self.navigationItem.titleView = nil;
    _connectingProgress.hidden = YES;
    
    OFSFileManager *fileManager = [[OUIWebDAVConnection sharedConnection] fileManager];
    NSURL *url = (_address != nil) ? _address : [fileManager baseURL];
    if (!url)
        return;
    
    NSString *newTitleName = [OFSFileInfo nameForURL:url];
    
    switch (_syncType) {
        case OUIiTunesSync:
            self.title = _isExporting ? NSLocalizedStringFromTableInBundle(@"Export to iTunes", @"OmniUI", OMNI_BUNDLE, @"iTunes export") : NSLocalizedStringFromTableInBundle(@"Copy from iTunes", @"OmniUI", OMNI_BUNDLE, @"iTunes export");
            break;
        case OUIMobileMeSync:
        case OUIOmniSync:
        case OUIWebDAVSync:
            self.title = _isExporting ? [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Export to '%@'", @"OmniUI", OMNI_BUNDLE, @"WebDAV export"), newTitleName] :[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Copy from '%@'", @"OmniUI", OMNI_BUNDLE, @"WebDAV export"), newTitleName];
            break;
        default:
            break;
    }
}

- (void)_goBack:(id)sender;
{
    [self.navigationController popViewControllerAnimated:YES];
}

@end
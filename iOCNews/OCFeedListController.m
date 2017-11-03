//
//  FeedListController.m
//  iOCNews
//

/************************************************************************
 
 Copyright 2012-2016 Peter Hedlund peter.hedlund@me.com
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 *************************************************************************/

#import "OCFeedListController.h"
#import "OCFeedCell.h"
#import "OCLoginController.h"
#import "TSMessage.h"
#import "OCNewsHelper.h"
#import "Folder.h"
#import "Feed.h"
#import <AFNetworking/AFNetworking.h>
#import "UIColor+PHColor.h"

static NSString *DetailSegueIdentifier = @"showDetail";

@interface OCFeedListController () <UIActionSheetDelegate, UISplitViewControllerDelegate> {
    NSNumber *currentRenameId;
    long currentIndex;
    BOOL networkHasBeenUnreachable;
    NSIndexPath *editingPath;
}

@property (strong, nonatomic) IBOutlet UIBarButtonItem *gearBarButtonItem;
@property (nonatomic, assign) BOOL collapseDetailViewController;

- (void) networkCompleted:(NSNotification*)n;
- (void) networkError:(NSNotification*)n;
- (void) doHideRead;
- (void) updatePredicate;
- (void) reachabilityChanged:(NSNotification *)n;
- (void) didBecomeActive:(NSNotification *)n;

@end

@implementation OCFeedListController

@synthesize feedRefreshControl;
@synthesize specialFetchedResultsController;
@synthesize foldersFetchedResultsController;
@synthesize feedsFetchedResultsController;
@synthesize folderId;
@synthesize feedSettingsAction;
@synthesize feedDeleteAction;
@synthesize collapseDetailViewController;

- (NSFetchedResultsController *)specialFetchedResultsController {
    if (!specialFetchedResultsController) {
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"Feed" inManagedObjectContext:[OCNewsHelper sharedHelper].context];
        [fetchRequest setEntity:entity];
        
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"myId < 0"];
        [fetchRequest setPredicate:pred];
        
        NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"myId" ascending:YES];
        [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sort]];
        [fetchRequest setFetchBatchSize:100];
        
        specialFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                                                              managedObjectContext:[OCNewsHelper sharedHelper].context
                                                                                sectionNameKeyPath:nil
                                                                                         cacheName:@"SpecialCache"];
        specialFetchedResultsController.delegate = self;
    }
    return specialFetchedResultsController;
}

- (NSFetchedResultsController *)foldersFetchedResultsController {
    if (!foldersFetchedResultsController) {
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"Folder" inManagedObjectContext:[OCNewsHelper sharedHelper].context];
        [fetchRequest setEntity:entity];

        NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"myId" ascending:YES];
        [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sort]];
        [fetchRequest setFetchBatchSize:20];
    
        foldersFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                                                              managedObjectContext:[OCNewsHelper sharedHelper].context
                                                                                sectionNameKeyPath:nil
                                                                                         cacheName:@"FolderCache"];
        foldersFetchedResultsController.delegate = self;
    }
    return foldersFetchedResultsController;
}

- (NSFetchedResultsController *)feedsFetchedResultsController {
    if (!feedsFetchedResultsController) {
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"Feed" inManagedObjectContext:[OCNewsHelper sharedHelper].context];
        [fetchRequest setEntity:entity];

        NSPredicate *pred = [NSPredicate predicateWithFormat:@"myId > 0"];
        [fetchRequest setPredicate:pred];

        NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"myId" ascending:YES];
        [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sort]];
        [fetchRequest setFetchBatchSize:20];
        
        feedsFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                                                            managedObjectContext:[OCNewsHelper sharedHelper].context
                                                                              sectionNameKeyPath:nil
                                                                                       cacheName:@"FeedCache"];
        feedsFetchedResultsController.delegate = self;
    }
    return feedsFetchedResultsController;
}

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.clearsSelectionOnViewWillAppear = NO;
    self.tableView.allowsSelection = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.scrollsToTop = YES;

    currentIndex = -1;
    networkHasBeenUnreachable = NO;
    
    int imageViewOffset = 14;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowFavicons"]) {
        imageViewOffset = 36;
    }
    self.tableView.separatorInset = UIEdgeInsetsMake(0, imageViewOffset, 0, 0);
    
    self.refreshControl = self.feedRefreshControl;
    
    self.splitViewController.presentsWithGesture = YES;
    self.splitViewController.delegate = self;
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeAutomatic;
    self.collapseDetailViewController = NO;
    
    [self applyTheme];
    
    //Notifications
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:@"HideRead"
                                               options:NSKeyValueObservingOptionNew
                                               context:NULL];

    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:@"SyncInBackground"
                                               options:NSKeyValueObservingOptionNew
                                               context:NULL];

    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:@"ShowFavicons"
                                               options:NSKeyValueObservingOptionNew
                                               context:NULL];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged:)
                                                 name:AFNetworkingReachabilityDidChangeNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(drawerOpened:)
                                                 name:@"DrawerOpened"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(drawerClosed:)
                                                 name:@"DrawerClosed"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(doRefresh:)
                                                 name:@"SyncNews"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(networkCompleted:)
                                                 name:@"NetworkCompleted"
                                               object:nil];

    [self updatePredicate];
}

- (void)dealloc
{
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"HideRead"];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"SyncInBackground"];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"ShowFavicons"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.feedsFetchedResultsController.delegate = nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTheme];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Return the number of sections.
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    switch (section) {
        case 0:
            return [self.specialFetchedResultsController fetchedObjects].count;
            break;
        case 1:
            return [self.foldersFetchedResultsController fetchedObjects].count;
            break;
        case 2:
            return [self.feedsFetchedResultsController fetchedObjects].count;
            break;
            
        default:
            return 0;
            break;
    }
    
    return 0;
}

- (void)configureCell:(OCFeedCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    @try {
        NSIndexPath *indexPathTemp = [NSIndexPath indexPathForRow:indexPath.row inSection:0];
        if (indexPathTemp.row < [self.tableView numberOfRowsInSection:indexPath.section]) {
            if (indexPath.section == 1) {
                Folder *folder = [self.foldersFetchedResultsController objectAtIndexPath:indexPathTemp];
                [cell.imageView setImage:[UIImage imageNamed:@"folder"]];
                cell.textLabel.text = folder.name;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.countBadge.value = folder.unreadCountValue;
            } else {
                Feed *feed;
                if (indexPath.section == 0) {
                    if (indexPath.row < 2) {
                        feed = [self.specialFetchedResultsController objectAtIndexPath:indexPathTemp];
                    }
                } else {
                    feed = [self.feedsFetchedResultsController objectAtIndexPath:indexPathTemp];
                }
                if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowFavicons"]) {
                    if (cell.tag == indexPathTemp.row) {
                        [[OCNewsHelper sharedHelper] faviconForFeedWithId:feed.myId imageView:cell.imageView];
                    }
                }
                cell.accessoryType = UITableViewCellAccessoryNone;
                if ((self.folderId > 0) && (indexPath.section == 0) && indexPath.row == 0) {
                    Folder *folder = [[OCNewsHelper sharedHelper] folderWithId:[NSNumber numberWithLong:self.folderId]];
                    cell.countBadge.value = folder.unreadCountValue;
                    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
                    if ([prefs boolForKey:@"HideRead"]) {
                        cell.textLabel.text = [NSString stringWithFormat:@"All Unread %@ Articles", folder.name];
                    } else {
                        cell.textLabel.text = [NSString stringWithFormat:@"All %@ Articles", folder.name];
                    }
                } else {
//                    NSLog(@"Unread count: %d", feed.unreadCountValue);
                    cell.countBadge.value = feed.unreadCountValue;
                    cell.textLabel.text = feed.title;
                }
            }
            cell.backgroundColor = [UIColor clearColor];
            cell.textLabel.textColor = [UIColor textColor];
//            cell.backgroundColor = [UIColor backgroundColor];
//            cell.contentView.backgroundColor = [UIColor cellBackgroundColor];
            cell.contentView.opaque = YES;
//            cell.imageView.backgroundColor = [UIColor popoverBackgroundColor];
//            cell.labelContainerView.backgroundColor = [UIColor cellBackgroundColor];
//            cell.buttonContainerView.backgroundColor = [UIColor cellBackgroundColor];

        }
    }
    @catch (NSException *exception) {
        //
    }
    @finally {
        //
    }

}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    OCFeedCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[OCFeedCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        UIView * selectedBackgroundView = [[UIView alloc] initWithFrame:cell.frame];
        [selectedBackgroundView setBackgroundColor:[UIColor colorWithRed:0.87f green:0.87f blue:0.87f alpha:1.0f]]; // set color here
        [cell setSelectedBackgroundView:selectedBackgroundView];
        cell.backgroundColor = [UIColor clearColor];
    }
    cell.tag = indexPath.row;
    [self configureCell:cell atIndexPath:indexPath];
    return cell;
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return @[self.feedDeleteAction, self.feedSettingsAction];
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return (indexPath.section > 0);
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSIndexPath *indexPathTemp = [NSIndexPath indexPathForRow:indexPath.row inSection:0];
        if (indexPath.section == 1) {
            [[OCNewsHelper sharedHelper] deleteFolderOffline:[self.foldersFetchedResultsController objectAtIndexPath:indexPathTemp]];
        } else if (indexPath.section == 2) {
            [[OCNewsHelper sharedHelper] deleteFeedOffline:[self.feedsFetchedResultsController objectAtIndexPath:indexPathTemp]];
        }
    }
}

// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
    //
}

// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return NO;
}


#pragma mark - Table view delegate

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView settingsActionPressedInRowAtIndexPath:(NSIndexPath *)indexPath {
    NSIndexPath *indexPathTemp = [NSIndexPath indexPathForRow:indexPath.row inSection:0];
    if ((indexPath.section == 1)) {
        Folder *folder = [self.foldersFetchedResultsController objectAtIndexPath:indexPathTemp];
        currentRenameId = folder.myId;
        [[self.renameFolderAlertView.textFields objectAtIndex:0] setText:folder.name];
        [self presentViewController:self.renameFolderAlertView animated:YES completion:nil];
        self.renameFolderAlertView.view.tintColor = [UINavigationBar appearance].tintColor;
    } else if (indexPath.section == 2) {
        currentIndex = indexPathTemp.row;
        [self performSegueWithIdentifier:@"feedSettings" sender:self];        
    }
    editingPath = indexPath;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    self.collapseDetailViewController = YES;
    if ([[segue identifier] isEqualToString:DetailSegueIdentifier]) {

        
        NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
        currentIndex = indexPath.row;
        NSIndexPath *indexPathTemp = [NSIndexPath indexPathForRow:currentIndex inSection:0];

        UINavigationController *navigationController = (UINavigationController *)segue.destinationViewController;
        self.detailViewController = (OCArticleListController *)navigationController.topViewController;
        self.detailViewController.feed = [self.feedsFetchedResultsController objectAtIndexPath:indexPathTemp];;
        self.detailViewController.navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
        self.detailViewController.navigationItem.leftItemsSupplementBackButton = YES;
        self.detailViewController.folderId = 0;

        if (self.tableView.isEditing) {
            //[self showRenameForIndex:indexPath.row];
        } else {
            Folder *folder;
            Feed *feed;


            
            switch (indexPath.section) {
                case 0:
                    @try {
                        if (self.splitViewController.displayMode == UISplitViewControllerDisplayModeAllVisible || self.splitViewController.displayMode == UISplitViewControllerDisplayModePrimaryOverlay) {
                            [UIView animateWithDuration:0.3 animations:^{
                                self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModePrimaryHidden;
                            } completion: nil];
                            feed = [self.specialFetchedResultsController objectAtIndexPath:indexPathTemp];
                            if (self.folderId > 0) {
                                self.detailViewController.folderId = self.folderId;
                            }
                            self.detailViewController.feed = feed;
                        }
                    }
                    @catch (NSException *exception) {
                        //
                    }
                    break;
                case 1:
                    @try {
                        if (self.folderId == 0) {
                            OCFeedListController *folderController = [self.storyboard instantiateViewControllerWithIdentifier:@"feed_list"];
                            folder = [self.foldersFetchedResultsController objectAtIndexPath:indexPathTemp];
                            folderController.folderId = folder.myIdValue;
                            folderController.navigationItem.title = folder.name;
                            [folderController updatePredicate];
                            folderController.detailViewController = self.detailViewController;
                            [self.navigationController pushViewController:folderController animated:YES];
                            [folderController drawerOpened:nil];
                            [self drawerClosed:nil];
                        }
                    }
                    @catch (NSException *exception) {
                        //
                    }
                    break;
                case 2:
                    @try {
                        if (self.splitViewController.displayMode == UISplitViewControllerDisplayModeAllVisible || self.splitViewController.displayMode == UISplitViewControllerDisplayModePrimaryOverlay) {
                            [UIView animateWithDuration:0.3 animations:^{
                                self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModePrimaryHidden;
                            } completion: nil];
                        }
                        feed = [self.feedsFetchedResultsController objectAtIndexPath:indexPathTemp];
                        self.detailViewController.feed = feed;
                        
                    }
                    @catch (NSException *exception) {
                        //
                    }
                    break;
                    
                default:
                    break;
            }
        }
    }
    if ([segue.identifier isEqualToString:@"feedSettings"]) {
        Feed *feed = [self.feedsFetchedResultsController.fetchedObjects objectAtIndex:currentIndex];
        UINavigationController *navController = (UINavigationController *)segue.destinationViewController;
        OCFeedSettingsController *settingsController = (OCFeedSettingsController*)navController.topViewController;
        settingsController.feed = feed;
        settingsController.delegate = self;
    }
}

#pragma mark - Actions

- (IBAction)onSettings:(id)sender {
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction* settingsAction = [UIAlertAction actionWithTitle:@"Settings"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {
                                                              
                                                              [self doSettings:action];
                                                              
                                                          }];
    
    [alert addAction:settingsAction];
 
    UIAlertAction* addFolderAction = [UIAlertAction actionWithTitle:@"Add Folder"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * action) {
                                                               
                                                               [self presentViewController:self.addFolderAlertView animated:YES completion:nil];
                                                               self.addFolderAlertView.view.tintColor = [UINavigationBar appearance].tintColor;
                                                           }];
    
    [alert addAction:addFolderAction];

    UIAlertAction* addFeedAction = [UIAlertAction actionWithTitle:@"Add Feed"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction * action) {
                                                                
                                                                [self presentViewController:self.addFeedAlertView animated:YES completion:nil];
                                                                self.addFeedAlertView.view.tintColor = [UINavigationBar appearance].tintColor;
                                                            }];
    
    [alert addAction:addFeedAction];

    NSString *hideReadTitle = [[NSUserDefaults standardUserDefaults] boolForKey:@"HideRead"] ? @"Show Read" : @"Hide Read";
    UIAlertAction* hideReadAction = [UIAlertAction actionWithTitle:hideReadTitle
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {
                                                              
                                                              [self doHideRead];
                                                              
                                                          }];
    
    [alert addAction:hideReadAction];

    alert.modalPresentationStyle = UIModalPresentationPopover;
    
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover)
    {
        popover.barButtonItem = (UIBarButtonItem *)sender;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    
    [self.navigationController presentViewController:alert animated:YES completion:^{
        alert.view.tintColor = [UINavigationBar appearance].tintColor;
    }];
    
    //Tint workaround from http://stackoverflow.com/a/32695820
//    [self.mm_drawerController presentViewController:alert animated:YES completion:^{
//        alert.view.tintColor = [UINavigationBar appearance].tintColor;
//    }];
    alert.view.tintColor = [UINavigationBar appearance].tintColor;
}

- (UIAlertController*)addFolderAlertView {
    static UIAlertController *alertController;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        alertController = [UIAlertController alertControllerWithTitle:@"Add New Folder" message:@"Enter the name of the folder to add." preferredStyle:UIAlertControllerStyleAlert];
        [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.keyboardType = UIKeyboardTypeDefault;
            textField.placeholder = @"Folder name";
        }];
        
        UIAlertAction *cancelButton = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *addButton = [UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[OCNewsHelper sharedHelper] addFolderOffline:[[alertController.textFields objectAtIndex:0] text]];
        }];
        [alertController addAction:cancelButton];
        [alertController addAction:addButton];
    });
    return alertController;
}

- (UIAlertController*)renameFolderAlertView {
    static UIAlertController *alertController;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        alertController = [UIAlertController alertControllerWithTitle:@"Rename Folder" message:@"Enter the new name of the folder." preferredStyle:UIAlertControllerStyleAlert];
        [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.keyboardType = UIKeyboardTypeDefault;
            textField.placeholder = @"Folder name";
        }];
        
        UIAlertAction *cancelButton = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [self.tableView setEditing:NO animated:YES];
        }];
        UIAlertAction *renameButton = [UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self.tableView setEditing:NO animated:YES];
            [[OCNewsHelper sharedHelper] renameFolderOfflineWithId:currentRenameId To:[[alertController.textFields objectAtIndex:0] text]];
        }];
        [alertController addAction:cancelButton];
        [alertController addAction:renameButton];
    });
    return alertController;
}

- (UIAlertController*)addFeedAlertView {
    static UIAlertController *alertController;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        alertController = [UIAlertController alertControllerWithTitle:@"Add New Feed" message:@"Enter the url of the feed to add." preferredStyle:UIAlertControllerStyleAlert];
        [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.keyboardType = UIKeyboardTypeURL;
            textField.placeholder = @"http://example.com/feed";
        }];
        
        UIAlertAction *cancelButton = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *addButton = [UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[OCNewsHelper sharedHelper] addFeedOffline:[[alertController.textFields objectAtIndex:0] text]];
        }];
        [alertController addAction:cancelButton];
        [alertController addAction:addButton];
    });
    return alertController;
}

- (void)doHideRead {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    BOOL hideRead = [prefs boolForKey:@"HideRead"];
    [prefs setBool:!hideRead forKey:@"HideRead"];
    [prefs synchronize];
    [[OCNewsHelper sharedHelper] renameFeedOfflineWithId:[NSNumber numberWithInt:-2] To:hideRead == YES ? @"All Articles" : @"All Unread Articles"];
}

- (IBAction)doSettings:(id)sender {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UINavigationController *nav;
    if ([sender isKindOfClass:[UIAlertAction class]]) {
        nav = [storyboard instantiateViewControllerWithIdentifier:@"login"];
        [nav.topViewController loadView];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
    } else {
        OCLoginController *lc = [storyboard instantiateViewControllerWithIdentifier:@"server"];
        nav = [[UINavigationController alloc] initWithRootViewController:lc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [self.navigationController presentViewController:nav animated:YES completion:nil];
}

- (IBAction)doRefresh:(id)sender {
    if (self.folderId == 0) {
        [[OCNewsHelper sharedHelper] sync:nil];
    } else {
        [[OCNewsHelper sharedHelper] updateFolderWithId:[NSNumber numberWithLong:self.folderId]];
    }
}

- (void) reloadRow:(NSIndexPath*)indexPath {
    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
    if (currentIndex >= 0) {
        [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:currentIndex inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    }

}

- (void) feedSettingsUpdate:(OCFeedSettingsController *)settings {
    [self.tableView reloadData];
    [self.tableView setEditing:NO animated:YES];
}

- (void)observeValueForKeyPath:(NSString *) keyPath ofObject:(id) object change:(NSDictionary *) change context:(void *) context {
    if([keyPath isEqual:@"HideRead"]) {
        [self updatePredicate];
    }
    if([keyPath isEqual:@"SyncInBackground"]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SyncInBackground"]) {
            [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
        } else {
            [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
        }
    }
    if([keyPath isEqual:@"ShowFavicons"]) {
        int imageViewOffset = 14;
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowFavicons"]) {
            imageViewOffset = 36;
        }
        self.tableView.separatorInset = UIEdgeInsetsMake(0, imageViewOffset, 0, 0);
        [self.tableView reloadData];
    }
}

- (void)updatePredicate {
    [NSFetchedResultsController deleteCacheWithName:@"SpecialCache"];
    [NSFetchedResultsController deleteCacheWithName:@"FolderCache"];
    [NSFetchedResultsController deleteCacheWithName:@"FeedCache"];
    NSPredicate *predFolder = [NSPredicate predicateWithFormat:@"folderId == %@", [NSNumber numberWithLong:self.folderId]];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"HideRead"]) {
        NSPredicate *pred1 = [NSPredicate predicateWithFormat:@"myId > 0"];
        NSPredicate *pred2 = [NSPredicate predicateWithFormat:@"unreadCount == 0"];
        NSArray *predArray = @[pred1, pred2];
        NSPredicate *pred3 = [NSCompoundPredicate andPredicateWithSubpredicates:predArray];
        NSPredicate *pred4 = [NSCompoundPredicate notPredicateWithSubpredicate:pred3];
        NSArray *predArray1 = @[predFolder, pred1, pred4];
        NSPredicate *pred5 = [NSCompoundPredicate andPredicateWithSubpredicates:predArray1];
        [[self.feedsFetchedResultsController fetchRequest] setPredicate:pred5];
    } else{
        NSPredicate *pred1 = [NSPredicate predicateWithFormat:@"myId > 0"];
        NSArray *predArray = @[predFolder, pred1];
        NSPredicate *pred3 = [NSCompoundPredicate andPredicateWithSubpredicates:predArray];
        [[self.feedsFetchedResultsController fetchRequest] setPredicate:pred3];
    }
    
    if (self.folderId > 0) {
        self.specialFetchedResultsController.fetchRequest.predicate = [NSPredicate predicateWithFormat:@"myId == -2"];
        self.foldersFetchedResultsController.fetchRequest.predicate = [NSPredicate predicateWithValue:NO];
    } else {
        self.specialFetchedResultsController.fetchRequest.predicate = [NSPredicate predicateWithFormat:@"myId < 0"];
        self.foldersFetchedResultsController.fetchRequest.predicate = nil;
    }
    
    NSError *error;
    if (![[self specialFetchedResultsController] performFetch:&error]) {
        // Update to handle the error appropriately.
//        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    if (![[self foldersFetchedResultsController] performFetch:&error]) {
        // Update to handle the error appropriately.
//        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    if (![[self feedsFetchedResultsController] performFetch:&error]) {
        // Update to handle the error appropriately.
//        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    
    [self.tableView reloadData];
}

- (void)reachabilityChanged:(NSNotification *)n {
    NSNumber *s = n.userInfo[AFNetworkingReachabilityNotificationStatusItem];
    AFNetworkReachabilityStatus status = [s integerValue];
    
    if (status == AFNetworkReachabilityStatusNotReachable) {
        networkHasBeenUnreachable = YES;
        [TSMessage showNotificationInViewController:self.navigationController title:@"Unable to Reach Server" subtitle:@"Please check network connection and login." type:TSMessageNotificationTypeWarning];
    }
    if (status > AFNetworkReachabilityStatusNotReachable) {
        if (networkHasBeenUnreachable) {
            [TSMessage showNotificationInViewController:self.navigationController title:@"Server Reachable" subtitle:@"The network connection is working properly." type:TSMessageNotificationTypeSuccess];
            networkHasBeenUnreachable = NO;
        }
    }
}

- (void) didBecomeActive:(NSNotification *)n {
    if ([[NSUserDefaults standardUserDefaults] stringForKey:@"Server"].length == 0) {
        [self doSettings:nil];
    } else {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SyncOnStart"]) {
            [[OCNewsHelper sharedHelper] performSelector:@selector(sync:) withObject:nil afterDelay:1.0f];
        }
        UIPasteboard *board = [UIPasteboard generalPasteboard];
        if (board.URL) {
            if (![board.URL.absoluteString isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"PreviousPasteboardURL"]]) {
                [[NSUserDefaults standardUserDefaults] setObject:board.URL.absoluteString forKey:@"PreviousPasteboardURL"];
                NSArray *feedURLStrings = [self.feedsFetchedResultsController.fetchedObjects valueForKey:@"url"];
                if ([feedURLStrings indexOfObject:[board.URL absoluteString]] == NSNotFound) {
                    NSString *message = [NSString stringWithFormat:@"Would you like to add the feed: '%@'?", [board.URL absoluteString]];
                    [TSMessage showNotificationInViewController:self.navigationController
                                                          title:@"Add Feed"
                                                       subtitle:message
                                                          image:nil
                                                           type:TSMessageNotificationTypeMessage
                                                       duration:TSMessageNotificationDurationAutomatic
                                                       callback:nil
                                                    buttonTitle:@"Add"
                                                 buttonCallback:^{
                                                 [[OCNewsHelper sharedHelper] addFeedOffline:[board.URL absoluteString]];
                                             }
                                                     atPosition:TSMessageNotificationPositionTop
                                            canBeDismissedByUser:YES];
                }
            }
        }
    }
}

- (void)drawerOpened:(NSNotification *)n {
    if ([self.navigationController.topViewController isEqual:self]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkError:) name:@"NetworkError" object:nil];
    }
    self.tableView.scrollsToTop = YES;
}

- (void)drawerClosed:(NSNotification *)n {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"NetworkError" object:nil];
    self.tableView.scrollsToTop = NO;
}

- (void)applyTheme {
    UIColor *bgColor = [UIColor backgroundColor];
    //self.navigationController.view.backgroundColor = bgColor;
    self.view.backgroundColor = bgColor;
    self.tableView.backgroundColor = bgColor;
    self.navigationController.navigationBar.barTintColor = bgColor;
    //bottomBorder.backgroundColor = [PHColors iconColor].CGColor;
    
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [UIColor clearColor];
    shadow.shadowBlurRadius = 0.0;
    shadow.shadowOffset = CGSizeMake(0.0, 0.0);
    
    [self.navigationController.navigationBar setTitleTextAttributes:
     [NSDictionary dictionaryWithObjectsAndKeys:
      [UIColor iconColor], NSForegroundColorAttributeName,
      shadow, NSShadowAttributeName, nil]];
    
    self.gearBarButtonItem.tintColor = [UIColor iconColor];
}


#pragma mark - Feeds maintenance

- (void) networkCompleted:(NSNotification *)n {
    [self.refreshControl endRefreshing];
    [self.detailViewController.refreshControl endRefreshing];
}

- (void)networkError:(NSNotification *)n {
    [TSMessage showNotificationInViewController:self.navigationController
                                          title:[n.userInfo objectForKey:@"Title"]
                                       subtitle:[n.userInfo objectForKey:@"Message"]
                                          image:nil
                                           type:TSMessageNotificationTypeError
                                       duration:TSMessageNotificationDurationEndless
                                       callback:nil
                                    buttonTitle:nil
                                 buttonCallback:nil
                                     atPosition:TSMessageNotificationPositionTop
                            canBeDismissedByUser:YES];
}

#pragma mark - Toolbar Buttons

- (UITableViewRowAction *)feedSettingsAction {
    if (!feedSettingsAction) {
        feedSettingsAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal
                                                                title:@"Settings"
                                                              handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
                                                                  [self tableView:self.tableView settingsActionPressedInRowAtIndexPath:indexPath];
                                                              }];
    }
    return feedSettingsAction;
}

- (UITableViewRowAction *)feedDeleteAction {
    if (!feedDeleteAction) {
        feedDeleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
                                                              title:@"Delete"
                                                            handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
                                                                [self tableView:self.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:indexPath];
                                                            }];
    }
    return feedDeleteAction;
}

- (UIRefreshControl *)feedRefreshControl {
    if (!feedRefreshControl) {
        feedRefreshControl = [[UIRefreshControl alloc] init];
        [feedRefreshControl addTarget:self action:@selector(doRefresh:) forControlEvents:UIControlEventValueChanged];
    }    
    return feedRefreshControl;
}


- (UISplitViewControllerDisplayMode)targetDisplayModeForActionInSplitViewController:(UISplitViewController *)svc {
    if (svc.displayMode == UISplitViewControllerDisplayModePrimaryHidden) {
        if (svc.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) {
            if (UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation)) {
                return UISplitViewControllerDisplayModeAllVisible;
            }
        }
        return UISplitViewControllerDisplayModePrimaryOverlay;
    }
    return UISplitViewControllerDisplayModePrimaryHidden;
}

- (BOOL)splitViewController:(UISplitViewController *)splitViewController collapseSecondaryViewController:(UIViewController *)secondaryViewController ontoPrimaryViewController:(UIViewController *)primaryViewController {
    return self.collapseDetailViewController;
}




- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    // The fetch controller is about to start sending change notifications, so prepare the table view for updates.
    [self.tableView beginUpdates];
}


- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath {

    UITableView *tableView = self.tableView;
    if (newIndexPath != nil && controller == self.foldersFetchedResultsController) {
        newIndexPath = [NSIndexPath indexPathForRow:[newIndexPath row] inSection:1];
        //if ([tableView cellForRowAtIndexPath:newIndexPath] == nil) {
        //    type = NSFetchedResultsChangeInsert;
        //}
    }
    if (newIndexPath != nil && controller == self.feedsFetchedResultsController) {
        newIndexPath = [NSIndexPath indexPathForRow:[newIndexPath row] inSection:2];
        //if ([tableView cellForRowAtIndexPath:newIndexPath] == nil) {
        //    type = NSFetchedResultsChangeInsert;
        //}
    }
    if (indexPath != nil && controller == self.foldersFetchedResultsController) {
        indexPath = [NSIndexPath indexPathForRow:[indexPath row] inSection:1];
    }
    if (indexPath != nil && controller == self.feedsFetchedResultsController) {
        indexPath = [NSIndexPath indexPathForRow:[indexPath row] inSection:2];
    }

    switch(type) {
            
        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeUpdate:
            [self configureCell:(OCFeedCell*)[tableView cellForRowAtIndexPath:indexPath] atIndexPath:indexPath];
            break;
            
        case NSFetchedResultsChangeMove:
            [tableView deleteRowsAtIndexPaths:[NSArray
                                               arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            [tableView insertRowsAtIndexPaths:[NSArray
                                               arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}


- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id )sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {
    
    switch(type) {
            
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
        default:
            break;
    }
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    // The fetch controller has sent all current change notifications, so tell the table view to process all updates.
    [self.tableView endUpdates];
}

@end

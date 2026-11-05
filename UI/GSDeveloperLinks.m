#import "GSDeveloperLinks.h"

static void GSLoadDeveloperAvatar(UITableViewCell *cell, NSString *urlString) {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                             cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                         timeoutInterval:8];
    [[[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              UIImage *avatar = error || !data.length ? nil : [UIImage imageWithData:data];
              if (!avatar)
                  return;
              dispatch_async(dispatch_get_main_queue(), ^{
                  UIListContentConfiguration *content =
                      [(UIListContentConfiguration *)cell.contentConfiguration copy];
                  content.image = avatar;
                  cell.contentConfiguration = content;
              });
          }] resume];
}

@implementation GSPanel (GSDeveloperLinks)
- (UITableViewCell *)developerCellForRow:(NSInteger)row {
    NSString *identifier = [NSString stringWithFormat:@"developer-%ld", (long)row];
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell)
        return cell;
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                  reuseIdentifier:identifier];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = @[ @"GitHub", @"X", @"Discord" ][row];
    content.secondaryText = @[ @"@tqmane", @"@t2aman1e", @"discord.gg/zJBrCaf6dz" ][row];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    content.image = [UIImage systemImageNamed:row == 2 ? @"bubble.left.and.bubble.right.fill"
                                                       : @"person.crop.circle.fill"];
    content.imageProperties.reservedLayoutSize = CGSizeMake(40, 40);
    content.imageProperties.maximumSize = CGSizeMake(40, 40);
    content.imageProperties.cornerRadius = 20;
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityTraits |= UIAccessibilityTraitLink;
    if (row < 2)
        GSLoadDeveloperAvatar(cell, row == 0 ? @"https://github.com/tqmane.png?size=128"
                                             : @"https://unavatar.io/x/t2aman1e?size=128");
    return cell;
}

- (void)openDeveloperProfileAtRow:(NSInteger)row {
    NSString *url = @[
        @"https://github.com/tqmane", @"https://x.com/t2aman1e", @"https://discord.gg/zJBrCaf6dz"
    ][row];
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:url]
                                     options:@{}
                           completionHandler:nil];
}
@end

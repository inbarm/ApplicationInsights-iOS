#import "AppInsightsPrivate.h"
#import "MSAISessionHelper.h"
#import "MSAISessionHelperPrivate.h"
#import "MSAIPersistence.h"

static NSString *const kMSAIFileName = @"MSAISessions";
static NSString *const kMSAIFileType = @"plist";
static char *const MSAISessionOperationsQueue = "com.microsoft.appInsights.sessionQueue";

@implementation MSAISessionHelper

#pragma mark - Initialize

+ (id)sharedInstance {
  static MSAISessionHelper *sharedInstance = nil;
  
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [self new];
  });
  
  return sharedInstance;
}

- (instancetype)init {
  if(self = [super init]) {
    NSSortDescriptor *dateSort= [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:NO];
    _sortDescriptors = [NSArray arrayWithObject:dateSort];
    _operationsQueue = dispatch_queue_create(MSAISessionOperationsQueue, DISPATCH_QUEUE_SERIAL);
    _sessionEntries = [[[MSAIPersistence sharedInstance] sessionIds] mutableCopy];
  }
  return self;
}

#pragma mark - edit property list

+ (void)addSessionId:(NSString *)sessionId withTimestamp:(NSString *)timestamp {
  [[self sharedInstance] addSessionId:sessionId withTimestamp:timestamp];
}

- (void)addSessionId:(NSString *)sessionId withTimestamp:(NSString *)timestamp {
  
  __weak typeof(self) weakSelf = self;
  dispatch_sync(self.operationsQueue, ^{
    typeof(self) strongSelf = weakSelf;
    
    [strongSelf.sessionEntries setObject:sessionId forKey:timestamp];
    [[MSAIPersistence sharedInstance] persistSessionIds:strongSelf.sessionEntries];
  });
}

+ (NSString *)sessionIdForTimestamp:(NSString *)timestamp {
  return [[self sharedInstance] sessionIdForTimestamp:timestamp];
}

- (NSString *)sessionIdForTimestamp:(NSString *)timestamp {
  __block NSString *sessionId = nil;
  
  __weak typeof(self) weakSelf = self;
  dispatch_sync(self.operationsQueue, ^{
    typeof(self) strongSelf = weakSelf;
    
    NSString *sessionKey = [strongSelf keyForTimestamp:timestamp];
    sessionId = [strongSelf.sessionEntries valueForKey:sessionKey];
  });
  
  return sessionId;
}

+ (void)removeSessionId:(NSString *)sessionId {
  [[self sharedInstance] removeSessionId:sessionId];
}

- (void)removeSessionId:(NSString *)sessionId {
  
  __weak typeof(self) weakSelf = self;
  dispatch_sync(self.operationsQueue, ^{
    typeof(self) strongSelf = weakSelf;
    
    // Find key for given sessionId
    // TODO: Maybe sorting dictionary keys in advance is faster
    NSString *sessionKey = nil;
    for(NSString *key in _sessionEntries) {
      if([strongSelf.sessionEntries[key] isEqualToString:sessionId]) {
        sessionKey = key;
        break;
      }
    }
    
    // Remove entry
    if(sessionKey){
      [strongSelf.sessionEntries removeObjectForKey:sessionKey];
      [[MSAIPersistence sharedInstance] persistSessionIds:strongSelf.sessionEntries];
    }
  });
}

+ (void)cleanUpSessionIds {
  [[self sharedInstance] cleanUpSessionIds];
}

- (void)cleanUpSessionIds {
  
  __weak typeof(self) weakSelf = self;
  dispatch_sync(self.operationsQueue, ^{
    typeof(self) strongSelf = weakSelf;
    
    // Get most recent session
    NSArray *sortedKeys = [strongSelf sortedKeys];
    NSInteger lastIndex = [sortedKeys indexOfObject:[sortedKeys lastObject]];
    NSString *lastKey = sortedKeys[lastIndex];
    
    // Clear list and add most recent session
    NSString *lastValue = strongSelf.sessionEntries[lastKey];
    [strongSelf.sessionEntries removeAllObjects];
    [strongSelf.sessionEntries setObject:lastValue forKey:lastKey];
      [[MSAIPersistence sharedInstance] persistSessionIds:strongSelf.sessionEntries];
  });
}

#pragma mark - Helper

- (NSString *)keyForTimestamp:(NSString *)timestamp {
  
  for(NSString *key in [self sortedKeys]){
    if([self iskey:key forTimestamp:timestamp]){
      return timestamp;
    }
  }
  return nil;
}

- (NSArray *)sortedKeys {
  NSMutableArray *keys = [[_sessionEntries allKeys] mutableCopy];
  [keys sortUsingDescriptors:_sortDescriptors];
  
  return keys;
}

- (BOOL)iskey:(NSString *)key forTimestamp:(NSString *)timestamp {
  return [timestamp longLongValue] > [key longLongValue];
}

@end

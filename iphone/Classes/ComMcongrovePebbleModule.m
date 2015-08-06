/**
 * Copyright 2014 Matthew Congrove
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *    http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "ComMcongrovePebbleModule.h"
#import "TiBase.h"
#import "TiHost.h"
#import "TiUtils.h"

#define MESSAGE_KEY @(0x0)

id updateHandler;

@implementation ComMcongrovePebbleModule

#pragma mark Internal

-(id)moduleGUID
{
	return @"01b0607f-455b-4c1e-8f26-a07128d90089";
}

-(NSString*)moduleId
{
	return @"com.mcongrove.pebble";
}

#pragma mark Cleanup 

-(void)dealloc
{
	[connectedWatch closeSession:^{}];
	[super dealloc];
}

#pragma mark Internal Memory Management

-(void)didReceiveMemoryWarning:(NSNotification*)notification
{
	[super didReceiveMemoryWarning:notification];
}

#pragma mark Lifecycle

-(void)startup
{
	NSLog(@"[DEBUG] Pebble.startup");

	[super startup];

	[[PBPebbleCentral defaultCentral] setDelegate:self];

	connectedWatch = [[PBPebbleCentral defaultCentral] lastConnectedWatch];
}

-(void)pebbleCentral:(PBPebbleCentral*)central watchDidConnect:(PBWatch*)watch isNew:(BOOL)isNew
{
	NSLog(@"[DEBUG] Pebble.watchDidConnect: %@", [watch name]);

	connectedWatch = watch;

	[self listenToConnectedWatch];

	NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:[watch name], @"name", nil];
	[self fireEvent:@"watchConnected" withObject:event];
}

-(void)pebbleCentral:(PBPebbleCentral*)central watchDidDisconnect:(PBWatch*)watch
{
	NSLog(@"[DEBUG] Pebble.watchDidDisconnect: %@", [watch name]);

	if(connectedWatch == watch || [watch isEqual:connectedWatch]) {
		[connectedWatch closeSession:^{}];

		connectedWatch = nil;
	}

	NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:[watch name], @"name", nil];
	[self fireEvent:@"watchDisconnected" withObject:event];
}

-(void)listenToConnectedWatch
{
	if(connectedWatch) {
		NSLog(@"[DEBUG] Pebble.listenToConnectedWatch: Listening");

		if(updateHandler) {
			[connectedWatch appMessagesRemoveUpdateHandler:updateHandler];

			updateHandler = nil;
		}

		updateHandler = [connectedWatch appMessagesAddReceiveUpdateHandler:^BOOL(PBWatch *watch, NSDictionary *dictionary) {
			NSLog(@"[DEBUG] Pebble.listenToConnectedWatch: Received message");

			NSMutableArray * messages = [NSMutableArray new];

			[dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
				[messages addObject:@{
					@"key": key,
					@"message": value
				}];
			}];

			[self fireEvent:@"update" withObject:@{
				@"messages": messages
			}];

			return YES;
		}];
	} else {
		NSLog(@"[WARN] Pebble.listenToConnectedWatch: No watch connected, not listening");
	}
}

-(void)shutdown:(id)sender
{
	[super shutdown:sender];
}

#pragma Public APIs

-(void)setAppUUID:(id)uuid
{
	ENSURE_SINGLE_ARG(uuid, NSString);

	NSString *uuidString = [TiUtils stringValue:uuid];
	NSUUID *myAppUUID = [[NSUUID alloc] initWithUUIDString:uuidString];
	uuid_t myAppUUIDbytes;

	[myAppUUID getUUIDBytes:myAppUUIDbytes];

	[[PBPebbleCentral defaultCentral] setAppUUID:[NSData dataWithBytes:myAppUUIDbytes length:16]];
}

-(BOOL)checkWatchConnected
{
	if(connectedWatch == nil) {
		NSLog(@"[WARN] Pebble.checkWatchConnected: No watch connected");

		return FALSE;
	} else {
		return TRUE;
	}
}

-(id)connectedCount
{
	NSArray *connected = [[PBPebbleCentral defaultCentral] connectedWatches];

	return NUMINT((int)connected.count);
}

-(void)connect:(id)args
{
	ENSURE_UI_THREAD_1_ARG(args);
	ENSURE_SINGLE_ARG(args, NSDictionary);

	@synchronized(connectedWatch) {
		NSLog(@"[DEBUG] Pebble.connect");

		id success = [args objectForKey:@"success"];
		id error = [args objectForKey:@"error"];

		RELEASE_TO_NIL(successCallback);
		RELEASE_TO_NIL(errorCallback);

		successCallback = [success retain];
		errorCallback = [error retain];

		[connectedWatch appMessagesGetIsSupported:^(PBWatch *watch, BOOL isAppMessagesSupported) {
			if(!isAppMessagesSupported) {
				NSLog(@"[ERROR] Pebble.connect: Watch does not support messages");

				if(errorCallback != nil) {
					[self _fireEventToListener:@"error" withObject:nil listener:errorCallback thisObject:nil];
				}

				return;
			}

			NSLog(@"[DEBUG] Pebble.connect: Messages supported");

			connectedWatch = watch;

			[self listenToConnectedWatch];

			if(successCallback != nil) {
				[self _fireEventToListener:@"success" withObject:nil listener:successCallback thisObject:nil];
			}
		}];
	}
}

-(void)getVersionInfo:(id)args
{
	if(![self checkWatchConnected]) {
		NSLog(@"[WARN] Pebble.getVersionInfo: No watch connected");

		return;
	}

	ENSURE_UI_THREAD_1_ARG(args);
	ENSURE_SINGLE_ARG(args, NSDictionary);

	@synchronized(connectedWatch) {
		NSLog(@"[DEBUG] Pebble.getVersionInfo");

		id success = [args objectForKey:@"success"];
		id error = [args objectForKey:@"error"];

		RELEASE_TO_NIL(successCallback);
		RELEASE_TO_NIL(errorCallback);

		successCallback = [success retain];
		errorCallback = [error retain];

		[connectedWatch getVersionInfo:^(PBWatch *watch, PBVersionInfo *versionInfo) {
			NSLog(@"[DEBUG] Pebble FW Major: %li", (long)versionInfo.runningFirmwareMetadata.version.major);
			NSLog(@"[DEBUG] Pebble FW Minor: %li", (long)versionInfo.runningFirmwareMetadata.version.minor);

			if(successCallback != nil) {
				NSDictionary *versionInfoDict = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSString stringWithFormat:@"%li", (long)versionInfo.runningFirmwareMetadata.version.major], @"major",
				[NSString stringWithFormat:@"%li", (long)versionInfo.runningFirmwareMetadata.version.minor], @"minor"];

				[self _fireEventToListener:@"success" withObject:versionInfoDict listener:successCallback thisObject:nil];
			}
		}
		onTimeout:^(PBWatch *watch) {
			NSLog(@"[WARN] Could not retrieve version info from Pebble");

			if(errorCallback != nil) {
				NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:@"Could not retrieve version info from Pebble", @"message",nil];
				[self _fireEventToListener:@"error" withObject:event listener:errorCallback thisObject:nil];
			}
		}
		];
	}
}

-(void)launchApp:(id)args
{
	if(![self checkWatchConnected]) {
		NSLog(@"[WARN] Pebble.launchApp: No watch connected");

		return;
	}

	ENSURE_UI_THREAD_1_ARG(args);
	ENSURE_SINGLE_ARG(args, NSDictionary);

	@synchronized(connectedWatch) {
		NSLog(@"[DEBUG] Pebble.launchApp");

		id success = [args objectForKey:@"success"];
		id error = [args objectForKey:@"error"];

		RELEASE_TO_NIL(successCallback);
		RELEASE_TO_NIL(errorCallback);

		successCallback = [success retain];
		errorCallback = [error retain];

		[connectedWatch appMessagesLaunch:^(PBWatch *watch, NSError *error) {
			if(!error) {
				NSLog(@"[DEBUG] Pebble.launchApp: Success");

				[self listenToConnectedWatch];

				if(successCallback != nil) {
					NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:@"Successfully launched app", @"message", nil];
					[self _fireEventToListener:@"success" withObject:event listener:successCallback thisObject:nil];
				}
			} else {
				NSLog(@"[ERROR] Pebble.launchApp: Error");

				if(errorCallback != nil) {
					NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:error.description, @"description", nil];
					[self _fireEventToListener:@"error" withObject:event listener:errorCallback thisObject:nil];
				}
			}
		}];
	}
}

-(void)killApp:(id)args
{
	if(![self checkWatchConnected]) {
		NSLog(@"[WARN] Pebble.killApp: No watch connected");

		return;
	}

	ENSURE_UI_THREAD_1_ARG(args);
	ENSURE_SINGLE_ARG(args, NSDictionary);

	@synchronized(connectedWatch) {
		NSLog(@"[DEBUG] Pebble.killApp");

		id success = [args objectForKey:@"success"];
		id error = [args objectForKey:@"error"];

		RELEASE_TO_NIL(successCallback);
		RELEASE_TO_NIL(errorCallback);

		successCallback = [success retain];
		errorCallback = [error retain];

		[connectedWatch appMessagesKill:^(PBWatch *watch, NSError *error) {
			if(!error) {
				NSLog(@"[DEBUG] Pebble.killApp: Success");
				
				if(successCallback != nil) {
					NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:@"Successfully killed app", @"message", nil];
					[self _fireEventToListener:@"success" withObject:event listener:successCallback thisObject:nil];
				}
			} else {
				NSLog(@"[ERROR] Pebble.killApp: Error");

				if(errorCallback != nil) {
					NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:error.description, @"description", nil];
					[self _fireEventToListener:@"error" withObject:event listener:errorCallback thisObject:nil];
				}
			}
		}];
	}
}

-(void)sendMessage:(id)args
{
	if(![self checkWatchConnected]) {
		NSLog(@"[WARN] Pebble.sendMessage: No watch connected");

		return;
	}

	ENSURE_UI_THREAD_1_ARG(args);
	ENSURE_SINGLE_ARG(args, NSDictionary);

	@synchronized(connectedWatch) {
		NSLog(@"[DEBUG] Pebble.sendMessage");

		id success = [args objectForKey:@"success"];
		id error = [args objectForKey:@"error"];

		RELEASE_TO_NIL(successCallback);
		RELEASE_TO_NIL(errorCallback);

		successCallback = [success retain];
		errorCallback = [error retain];

		NSDictionary *message = [args objectForKey:@"message"];
		NSMutableDictionary *update = [[NSMutableDictionary alloc] init];
		NSMutableArray *keys = [[message allKeys] mutableCopy];

		for (NSString *key in keys) {
			id obj = [message objectForKey:key];

			NSNumber *updateKey = @([key integerValue]);

			if([obj isKindOfClass:[NSString class]]) {
				NSString *objString = [[NSString alloc] initWithString:obj];

				[update setObject:objString forKey:updateKey];
			}

			if([obj isKindOfClass:[NSNumber class]]) {
				NSNumber *objNumber = [[NSNumber alloc] initWithInteger:[obj integerValue]];

				[update setObject:objNumber forKey:updateKey];
			}
		}

		[connectedWatch appMessagesPushUpdate:update onSent:^(PBWatch *watch, NSDictionary *update, NSError *error) {
			if(!error) {
				NSLog(@"[DEBUG] Pebble.sendMessage: Success");

				[self _fireEventToListener:@"success" withObject:nil listener:successCallback thisObject:nil];
			} else {
				NSLog(@"[ERROR] Pebble.sendMessage: Error: %@", error);

				[self _fireEventToListener:@"error" withObject:error listener:errorCallback thisObject:nil];
			}
		}];
	}
}

@end
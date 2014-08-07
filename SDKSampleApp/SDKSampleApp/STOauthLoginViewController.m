//
//  STViewController.m
//  SimplerTransaction
//
//  Created by Cotter, Vince on 11/14/13.
//  Copyright (c) 2013 PayPal Partner. All rights reserved.
//

#import "PPSPreferences.h"
#import "PPSCryptoUtils.h"

#import "AFNetworking.h"
#import "STOauthLoginViewController.h"
#import "TransactionViewController.h"
#import "STAppDelegate.h"
#import "DemosTableViewController.h"

#import <PayPalHereSDK/PayPalHereSDK.h>
#import <PayPalHereSDK/PPHPaymentLimits.h>

@interface STOauthLoginViewController ()

@property (nonatomic, strong) UIPickerView *pickerView;
@property (nonatomic, strong) NSArray *pickerViewArray;
@property (nonatomic, strong) NSArray *pickerURLArray;
@property (nonatomic, strong) NSArray *serviceArray;
@property (nonatomic, strong) NSString *serviceHost;
@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;

@end

/**
 * For proper security, you need a server that securely stores the app id and secret for
 * PayPal Access. In order to prevent other applications and/or web sites from using your
 * back end service for their own purposes, and given that you likely have your own account
 * system, you should have the merchant login to your services first, and then authenticate
 * them when handing out URLs and exchanging tokens for authentication tokens.
 *
 *
 *
 * The service this sample code logs into:
 *
 * This example login code logs into a pretend business system that simulates your service.  
 * The pretend business server is the sample server included with the PayPalHere SDK.
 * You can find the example node service here: SDKROOT/sample-server
 * 
 * You can run this service locally on your development machine, on a network, or you can make
 * use of already running sample servers the PayPal Here team has hosted on heroku.  This example
 * code does make use of those already-running example servers.  
 *
 *
 * What this login code does:
 *
 * Step 1:
 * We first make a /login call to the sample service.  This is a pretend merchant login to
 * a business system and is not paypal specific.  You pass up your username and password in this call.
 * What is returned is JSON which contains a 'ticket' for your merchant.   This ticket is used is
 * follow up calls to the sample service.
 *
 * The JSON will also contain information about this merchant.  The sample service currently returns
 * the merchant's contact information.
 *
 * If this merchant was recently logged into PayPal then the JSON returned may contain an access token.
 * If so, then we call setActiveMerchant to provide this access_token (and the merchant
 * contact info) to the PayPalHere SDK.  We then are done with login and push the TransactionViewController
 * which allows you to build a purchase order.
 *
 * Step 2:
 * If we did not receive an access_token from the sample service then we will need to ask the sample 
 * service to log the merchant into PayPal via PayPal's oauth process.  To do that we make a /goPayPal
 * call against the sample service.  The service will return a PayPal oauth login URL to us.  We then 
 * have mobile Safari use this URL to allow the merchant to log into PayPal via the oauth process.
 *
 * Once logged in PayPal will return the refresh and access credentials to the sample service.  The idea
 * is that the sample service (in a real shipping system, your business server) will hold these credentials
 * for the merchant.  The sample server makes note of these credentials then does a URL redirect back to
 * the sample app.   This redirect is handled by the STAppDelegate.  Please see the handleOpenURL method 
 * there.
 *
 * Step 3:
 * Once our app is relaunched via the app delegate's handleOpenURL, we will be passed
 * the access_token needed by the SDK.  The app delegate will call this View Controller's 
 * setActiveMerchantWithAccessTokenDict method.  We'll then set these credentails into the SDK
 * and will launch the TransactionViewController which allows you to build a purchase order and is the
 * launching point for the rest of the sample app.
 *
 */
@implementation STOauthLoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.title = @"Merchant Login";
	self.usernameField.delegate = self;
	self.passwordField.delegate = self;

	[self.scrollView 
		 setContentSize:CGSizeMake(CGRectGetWidth(self.scrollView.frame),
								   CGRectGetHeight(self.scrollView.frame)
			)];

	[self createPicker];    // This is the barrel roller which allows selection of Live, Sandbox, and Stage

	// Initialize the URL label to the currently selected Service:
	NSString *initialServiceHost = [self.pickerURLArray objectAtIndex:[self.pickerView selectedRowInComponent:0]];
	self.serviceURLLabel.text = initialServiceHost;
	self.serviceHost = initialServiceHost;

    // Make the merchant checked in flag to false, since if we are in login screen then this should be the starting poing
    STAppDelegate *appDelegate = (STAppDelegate *)[[UIApplication sharedApplication] delegate];
    appDelegate.isMerchantCheckedin = NO;
    appDelegate.merchantLocation = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Did we successfully log in in the past?  If so, let's prefill the username box with
    // that last-good user name.
    NSString *lastGoodUserName = [[NSUserDefaults standardUserDefaults] stringForKey:@"lastgoodusername"];
    if (lastGoodUserName) {
        self.usernameField.text = lastGoodUserName;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

/*
 * Called in reaction to the user tapping the 'login' button
 */
- (IBAction)loginPressed:(id)sender {

    if (!self.usernameField.text.length) {
        [self.usernameField becomeFirstResponder];
    }
    else if (!self.passwordField.text.length) {
        [self.passwordField becomeFirstResponder];
    }
    else {
        [self dismissKeyboard];
    }

	self.loginInProgress.hidden = NO;
    [self.loginInProgress startAnimating];
    self.loginButton.enabled = NO;

	NSLog(@"Attempting to log-in via service at [%@]", self.serviceHost);
    STAppDelegate *appDelegate = (STAppDelegate *)[[UIApplication sharedApplication] delegate];
    appDelegate.serviceURL = self.serviceHost;
    
    // This is the STEP 1 referenced in the documentation at the top of the file.  This executes a /login
    // call against the sample business service.  This isn't a paypal loging, but instead triggers a business
    // system login.
    //
    AFHTTPClient *httpClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString: self.serviceHost]];
    httpClient.parameterEncoding = AFJSONParameterEncoding;
    NSMutableURLRequest *request = [httpClient requestWithMethod:@"POST" path:@"login" parameters:@{
                             @"username": self.usernameField.text,
                             @"password": self.passwordField.text
                             }];
    request.timeoutInterval = 10;
    
    
    [self configureServers:_pickerView];
    
    // Execute that /login call
    //
    AFJSONRequestOperation *operation = 
	  [AFJSONRequestOperation JSONRequestOperationWithRequest:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, NSDictionary *JSON) {

		  self.loginInProgress.hidden = YES;
          [self.loginInProgress stopAnimating];
          self.loginButton.enabled = YES;
          
          // Did we get a successful response with no data?
		  if (!JSON) {
              // Strange!  Fail the login attempt and alert the user.
              [self showAlertWithTitle:@"Heroku Login Failed"
                            andMessage:[NSString stringWithFormat:
                                        @"Server returned an ambiguous response (nil JSON dictionary). "
                                        @"Check your Username and Password and try again. "
                                        @"If problem continues, might be a good idea to see if the server is healthy [%@]",
                                        self.serviceHost]];
              
			  NSLog(@"Apparently logged into Heroku successfully - but we got a nil JSON dict");
              return;
          }
          
          // We received JSON from the sample server.  Let's extract the merchant information
          // and, if it exists, the access_token.
          //
          if ([JSON objectForKey:@"merchant"]) {

              // Let's see if we can pull out everything that we need
              NSString *ticket = [JSON objectForKey:@"ticket"];
              
              // This is your credential for your service. We'll need it later for your server to give us an OAuth token
              // if we don't have one already
              [PPSPreferences setCurrentTicket:ticket];
              
              if (ticket == nil) {
                  [self showAlertWithTitle:@"Missing PayPal Login Info"
                                andMessage:@"Logging in to PayPal requires a non-nil ticket token, but OAuth returned a nil ticket."];
              }
              else {

                  // We've got a ticket, we've got a merchant - let's fill out our merchant object which we'll
                  // give to the SDK once we complete the login process.
                  //
                  NSDictionary *yourMerchant = [JSON objectForKey:@"merchant"];

                  self.merchant = [[PPHMerchantInfo alloc] init];
                  self.merchant.invoiceContactInfo = [[PPHInvoiceContactInfo alloc]
                                                  initWithCountryCode: [yourMerchant objectForKey:@"country"]
                                                  city:[yourMerchant objectForKey:@"city"]
                                                  addressLineOne:[yourMerchant objectForKey:@"line1"]];
                  self.merchant.invoiceContactInfo.businessName = [yourMerchant objectForKey:@"businessName"];
                  self.merchant.invoiceContactInfo.state = [yourMerchant objectForKey:@"state"];
                  self.merchant.invoiceContactInfo.postalCode = [yourMerchant objectForKey:@"postalCode"];
                  self.merchant.currencyCode = [yourMerchant objectForKey:@"currency"];

                  if ([JSON objectForKey:@"access_token"]) {
                      // The access token exists!   The user must have previously logged into
                      // the sample server.  Let's give these credentials to the SDK and conclude
                      // the login process.
                      [self setActiveMerchantWithAccessTokenDict:JSON];
                  }
                  else {
                      // We don't have an access_token?  Then we need to login to PayPal's oauth process.
                      // Let's procede to that step.
                      [self loginToPayPal:ticket];
                  }
              }
          }
          else {
              self.merchant = nil;
              
              [self showAlertWithTitle:@"Heroku Login Failed"
                            andMessage:@"Check your Username and Password and try again."];

              NSLog(@"Heroku login attempt failed.");
          }
		  

		} failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {

		  self.loginInProgress.hidden = YES;

            [self showAlertWithTitle:@"Heroku Login Failed"
                          andMessage:[NSString stringWithFormat: @"The Server returned an error: [%@]",
                                      [error localizedDescription]]];

            NSLog(@"The Heroku login call failed: [%@]", error);
            self.loginButton.enabled = YES;


		}];
    
    [operation start];



}

/*
 * Called when we have JSON that contains an access token.  Which this is
 * the case we'll attempt to decrypt the access token and configure the SDK
 * to use it.  If successful this call will conclude the login process and 
 * launch the TransactionViewController which is then entry point into the 
 * rest of the SDK.
 */
- (void) setActiveMerchantWithAccessTokenDict:(NSDictionary *)JSON
{
	NSString* key = [PPSPreferences currentTicket]; // The sample server encrypted the access token using the 'ticket' it returned in step 1 (the /login call)
	NSString* access_token = [JSON objectForKey:@"access_token"];
	NSString* access = [PPSCryptoUtils AES256Decrypt:access_token  withPassword:key];
                          
	if (key == nil || access == nil) {
        
		NSLog(@"Bailing because couldn't decrypt access_code.   key: %@   access: %@   access_token: %@", key, access, access_token);

		self.loginInProgress.hidden = YES;

        [self showAlertWithTitle:@"Press the Login Button Again"
                      andMessage:@"Looks like something went wrong during the redirect.  Tap Login again to retry."];
						
		return;
	}

    // We have valid credentials.
    // The login process has been successful.  Here we complete the process.
    // Let's package them up the credentails into a PPHAccessAcount object and set that
    // object into the PPHMerchant object we're building.
	PPHAccessAccount *account = [[PPHAccessAccount alloc] initWithAccessToken:access
														  expires_in:[JSON objectForKey:@"expires_in"]
														  refreshUrl:[JSON objectForKey:@"refresh_url"] details:JSON];
	self.merchant.payPalAccount = account;  // Set the credentails into the merchant object.

    // Since this is a successful login, let's save the user name so we can use it as the default username the next
    // time the sample app is run.
    [[NSUserDefaults standardUserDefaults] setObject:self.usernameField.text forKey:@"lastgoodusername"];
    
    // Call setActiveMerchant
    // This is how we configure the SDK to use the merchant info and credentails.
    // Provide the PPHMerchant object we've built, and a key which the SDK will use to uniquely store this merchant's
    // contact information.
    // NOTE: setActiveMerchant will kick off two network requests to PayPal.  These calls request detailed information
    // about the merchant needed so we can take payment for this merchant.  Once those calls are done the completionHandler
    // block will be called.  If successful, status will be ePPHAccessResultSuccess.  Only if this returns successful
    // will the SDK be able to take payment, do invoicing related operations, or do checkin operations for this merchant.
    //
    // Please wait for this call to complete before attempting other SDK operations.
    //
	[PayPalHereSDK setActiveMerchant:self.merchant 
				   withMerchantId:self.merchant.invoiceContactInfo.businessName
				   completionHandler: ^(PPHAccessResultType status, PPHAccessAccount* account, NSDictionary* extraInfo) {

			if (status == ePPHAccessResultSuccess) {
                // Login complete!
                
                // Save the capture tolerance, which we might need to display for this merchant on the settings page.
                STAppDelegate *appDelegate = (STAppDelegate *)[[UIApplication sharedApplication] delegate];
                appDelegate.captureTolerance = [[account paymentLimits] captureTolerance];

                // Time to show the sample app UI!
                //
				[self transitionToTransactionViewController];
			}

			else {

				NSLog(@"We have FAILED to setActiveMerchant from setActiveMerchantWithAccessTokenDict, showing error Alert.");

                [self showAlertWithTitle:@"No PayPal Merchant Account"
                              andMessage:@"Can't attempt any transactions till you've set up a PayPal Merchant account!"];

			}

		}];

}

/*
 * Called when we need to obtain pay pal credentials for this merchant.  
 * This will execute a /goPayPal call against the sample server running
 * on heroku.  If successful the sample server will return a URL for our 
 * merchant to use to log in to PayPal's oauth process.  We direct Safari
 * to that URL.  The mobile web page, running in safari, will ask the 
 * merchant to log into their PayPal account.   If the merchant agrees, and 
 * the login is successful, Safari will redirect back to our app.  In that 
 * case iOS will launch our app via the AppDelegate's handleOpenURL call.
 */
- (void) loginToPayPal:(NSString *)ticket
{
  	NSLog(@"Logging in to PayPal...");
    
    AFHTTPClient *httpClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString: self.serviceHost]];
    httpClient.parameterEncoding = AFJSONParameterEncoding;
    NSMutableURLRequest *request = [httpClient requestWithMethod:@"POST" path:@"goPayPal" parameters:@{
                                                                                                       @"username": self.usernameField.text,
                                                                                                       @"ticket": ticket
                                                                                                       }];
    request.timeoutInterval = 10;
	
    AFJSONRequestOperation *operation =
    [AFJSONRequestOperation JSONRequestOperationWithRequest:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, NSDictionary *JSON) {
        
        if (JSON) {
			NSLog(@"PayPal login attempt got some JSON back: [%@]", JSON);
            
			if ([JSON objectForKey:@"url"] && [[JSON objectForKey:@"url"] isKindOfClass:[NSString class]]) {
                
                // FIRE UP SAFARI TO LOGIN TO PAYPAL
                // \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_
                NSString *url = [JSON objectForKey:@"url"];
                NSLog(@"Pointing Safari at URL [%@]", url);
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
			}
			else {
                
                // UH-OH - NO URL FOR SAFARI TO FOLLOW, NO ACCESS TOKEN FOR YOU. FAIL.
                // \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ \_\_ 
                NSLog(@"FAILURE! Got neither a URL to point Safari to, nor an Access Token - Huh?");
                
                [self showAlertWithTitle:@"PayPal Login Failed"
                              andMessage:@"Didn't get a URL to point Safari at, nor an Access Token - unable to proceed.  Server down?"];
                
			}
            
        }
        else {
			NSLog(@"PayPal login attempt got no JSON back!");
        }
        
        
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        
        NSLog(@"The PayPal login attempt failed: [%@]", error);
        
    }];
    
    [operation start];
    
	NSLog(@"Attempting to login to Paypal as \"%@\" with ticket \"%@\"...", self.usernameField.text, ticket);
}

-(void) showAlertWithTitle:(NSString *)title andMessage:(NSString *)message {
    UIAlertView *alertView =
    [[UIAlertView alloc]
     initWithTitle:title
     message: message
     delegate:nil
     cancelButtonTitle:@"OK"
     otherButtonTitles:nil];
    
    [alertView show];
}

/*
 * When done with the login process we'll call this method to enter the bulk of
 * the sample app.
 */
- (void)transitionToTransactionViewController
{

    DemosTableViewController *vc = [[DemosTableViewController alloc] init];
    self.navigationController.viewControllers = @[vc];

}

- (void)dismissKeyboard
{
    [self.usernameField resignFirstResponder];
    [self.passwordField resignFirstResponder];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if ([self.usernameField isFirstResponder]) {
        [self.passwordField becomeFirstResponder];
    } 
    else {
        [self dismissKeyboard];
    }
    
    return NO;
}


#pragma mark - UIPickerView

#define stageIndex 0
#define sandboxIndex 1
#define liveIndex 2

/*
 * There are currently 3 sample servers (based on the SDK's included node sample-server) for
 * this sample app to login against.  If you stand up your own version of the sample-server you
 * can modify this data to include your own server.  If you're running the sample-server on your
 * own laptop you can create a localhost entry as well.
 */
- (void)createPicker
{
  self.pickerViewArray = 
	  @[ 
		  @"Stage", 
		   @"Sandbox", 
		  @"Live"
		  ];

  self.pickerURLArray = 
	  @[ 
		  @"http://agile-mountain-7526.herokuapp.com", 
		   @"http://desolate-wave-3684.herokuapp.com", 
		  @"http://stormy-hollows-1584.herokuapp.com"
		  ];
    
  self.serviceArray =
    @[
       [NSURL URLWithString:STAGE],
       [NSURL URLWithString:SANDBOX],
       [NSNull null]
    ];

  // note we are using CGRectZero for the dimensions of our picker view,                                                                   
  // this is because picker views have a built in optimum size,                                                                            
  // you just need to set the correct origin in your view.                                                                                 
  //                                                                                                                                       
  self.pickerView = [[UIPickerView alloc] initWithFrame:CGRectZero];

  [self.pickerView sizeToFit];

  self.pickerView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;

  self.pickerView.showsSelectionIndicator = YES;    // note this is defaulted to NO                                                      

  // this view controller is the data source and delegate                                                                                  
  self.pickerView.delegate = self;
  self.pickerView.dataSource = self;

  [self.scrollView addSubview:self.pickerView];
}

/* 
 * When we change what service we're using we need to
 * tell the SDK.  That way the SDK knows what URL base 
 * to use for all its calls.   Whenever the user scrolls
 * the barrel roller and picks a new server this method is
 * called. 
 */
-(void)configureServers:(UIPickerView *)pickerView {
    int index = [pickerView selectedRowInComponent:0];
    
    NSLog(@"%@",
		  [NSString stringWithFormat:@"%@",
           [self.pickerViewArray objectAtIndex:index]]);
    
	NSString *serviceURL = [self.pickerURLArray objectAtIndex:index];
	self.serviceURLLabel.text = serviceURL;
	self.serviceHost = serviceURL;
    
    NSURL *testBaseUrlForTheSDKToUse = [self.serviceArray objectAtIndex:index];
    
    
    //If we want Live then use nil as the base URL.
    if ([[NSNull null] isEqual:testBaseUrlForTheSDKToUse]) {
        testBaseUrlForTheSDKToUse = nil;
    }
    
    NSLog(@"urlForTheSDKToUse: %@", testBaseUrlForTheSDKToUse);
    
    /*
     * Deprecated.  Only used when dealing with test stages.  In a shipping app don't call it.
     */
    [PayPalHereSDK setBaseAPIURL:nil];  //Clear out any stage URL we might have set.
    
    if(index == liveIndex) {
        [PayPalHereSDK selectEnvironmentWithType:ePPHSDKServiceType_Live];
        return;
    }
    else if(index == sandboxIndex) {
        [PayPalHereSDK selectEnvironmentWithType:ePPHSDKServiceType_Sandbox];
        return;
    }
    else if(index == stageIndex) {
        /*
         * Deprecated.  Only used when dealing with test stages.  In a shipping app don't call it.
         */
        [PayPalHereSDK setBaseAPIURL:testBaseUrlForTheSDKToUse];
        return;
    }
}

#pragma mark - UIPickerViewDelegate

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
	[self configureServers:pickerView];
}

#pragma mark - UIPickerViewDataSource

- (NSAttributedString *)pickerView:(UIPickerView *)pickerView attributedTitleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    NSMutableAttributedString *attrTitle = nil;

	NSString *title = [self.pickerViewArray objectAtIndex:row];
	attrTitle = [[NSMutableAttributedString alloc] initWithString:title];
	[attrTitle addAttribute:NSForegroundColorAttributeName
			   value:[UIColor blackColor]
			   range:NSMakeRange(0, [attrTitle length])];

	return attrTitle;

}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
	return [self.pickerViewArray objectAtIndex:row];
}

- (CGFloat)pickerView:(UIPickerView *)pickerView widthForComponent:(NSInteger)component
{
	return self.pickerView.frame.size.width;
}

- (CGFloat)pickerView:(UIPickerView *)pickerView rowHeightForComponent:(NSInteger)component
{
	return 40.0;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{   
    return [self.pickerViewArray count];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{   
    return 1;
}


@end

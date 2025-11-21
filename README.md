# foo-cover-browser
Cover Art Browser for Foobar2000 Mac

## How to Use
1. Install the component on Foorbar2000 (Settings -> Components -> +)
2. After Foobar2000 restarts, you can access the Cover Browser from "View" menu.
3. You can change the sort of albums.
4. You can right click on each album and choose between:
 * Play
 * Send to Current Playlist
 * Add to Current Playlist
 * Send to New Playlist
<img width="1012" height="764" alt="CoverBrowser" src="https://github.com/user-attachments/assets/fdabdb76-8994-4040-8bdc-cb7eb1fcee32" />


## How to build
1. Download the source code from this github project.
2. Download the [Foobar2000 SDK] (https://www.foobar2000.org/SDK).
3. Extract the Foobar2000 SDK, copy cover_browser to SDK-date/foobar2000 folder.
4. Open the coverbrowser.xcworkspace file inside cover_browser folder with XCode.
5. Choose foo_sample as the target.
6. Click the menu Product > Build For > Running.
7. After build is done, click on Product > Show Build folder.
8. Navigate the folder that opens until you reach a folder with the component extension, that's your file to give to Foobar2000.

# foo-cover-browser
Cover Art Browser for Foobar2000 Mac

## How to Use
1. Download the component from the [releases](https://github.com/openmac/foo-cover-browser/releases) or build it yourself.
2. Install the component on Foorbar2000 (Settings -> Components -> +)
3. After Foobar2000 restarts, you can access the Cover Browser from "View" menu.
4. You can change the sort of albums.
5. You can search by Album title or Artist.
6. You can right click on each album and choose between:
 * Play
 * Send to Current Playlist
 * Add to Current Playlist
 * Send to New Playlist
<img width="1012" height="764" alt="Screenshot 2025-12-05 at 1 16 24 AM" src="https://github.com/user-attachments/assets/288b8391-0732-4ab1-9cc3-edc13517d288" />

7. You can click on the settings icon to set the Cover Browser to open at Foobar2000's startup:
<img width="468" height="102" alt="Screenshot 2025-12-05 at 1 15 17 AM" src="https://github.com/user-attachments/assets/979e95aa-0f05-4146-a847-8e1364c962f6" />



## How to build
1. Download the source code from this github project.
2. Download the [Foobar2000 SDK](https://www.foobar2000.org/SDK).
3. Extract the Foobar2000 SDK, copy cover_browser to SDK-date/foobar2000 folder.
4. Open the coverbrowser.xcworkspace file inside cover_browser folder with XCode.
5. Choose foo_sample as the target:
<img width="479" height="365" alt="Screenshot 2025-12-04 at 2 22 29 PM" src="https://github.com/user-attachments/assets/19400ebc-174c-4b74-96bb-e68eb578355a" />

6. Click the menu Product > Build For > Running.
7. After build is done, click on Product > Show Build folder.
8. Navigate the folder that opens until you reach a folder with the component extension, that's your file to give to Foobar2000.


## Credits
This was originally built with GPT 5 Codex and later fixed and improved with Claude Sonnet 4.5 and Gemini 3 Pro, I just gave them the prompts and made small modifications here and there.

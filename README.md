# ACHLSCaptioningServer            
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-iOS--tvOS-br.svg)
![Language](https://img.shields.io/badge/language-Objective--C-brightgreen.svg )

ACHLSCaptioningServer is an easy-to-use utility for dynamically adding VTT subtitles to HLS (m3u8) streams that do not have subtitles embedded already. This class generates a new HLS file and upload that file to a local server using GCDWebServer. The generated file URL can be passed to an AVPlayerViewController object.

Last tested on Xcode 7.3, iOS 9.3.2, tvOS 9.2.1

## Installation and Setup

#### Manual
1. Add ACHLSCaptioningServer folder to your project.
2. In the project editor, select your target, click Build Phases and then under Link Binary With Libraries add libz.tbd and libxml2.tbd libraries to your target. (This is needed for GCDWebServer)

## Usage
```objective-c

NSURL *origStreamURL = your-original-stream-url
NSURL *vttFileURL = your-vtt-file-url

NSURL *streamURL = [[ACHLSCaptioningServer sharedInstance] getCaptionedHLSStreamFromStream:origStreamURL vttURL:vttFileURL];

AVURLAsset *videoAsset = [[AVURLAsset alloc] initWithURL:streamURL options:nil];

AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:videoAsset];

AVPlayer *player = [AVPlayer playerWithPlayerItem:playerItem];

AVPlayerViewController *avPlayerController = [[AVPlayerViewController alloc] initWithNibName:nil bundle:nil];
[avPlayerController setPlayer:player];
[avPlayerController.view setFrame:self.view.frame];
[self addChildViewController:avPlayerController];
[self.view addSubview:avPlayerController.view];
[avPlayerController didMoveToParentViewController:self];

```

### Licensing
This project is licensed under the terms of the MIT license.

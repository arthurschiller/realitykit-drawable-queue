
# RealityKit 2 DrawableQueue: Animated GIFs

A sample project demonstrating a usecase for the [DrawableQueue](https://developer.apple.com/documentation/realitykit/textureresource/drawablequeue) API in RealityKit 2  – which currently lacks Documentation – by implementing support for animated GIFs.

> **Disclaimer:** While this implementation certainly performs rather well there are probably a lot of optimizations that could be made
> here. Currently a MTLTexture is being created for every frame of a gif
> which might not be the best way to do this – I'm still learning and do
> not have an in-depth knowledge of Metal.


*Proper code commenting and maybe a tutorial will follow. *

## Requirements:
Xcode 13 Beta 5 and a device running iOS 15

## Preview:  
![Preview](./preview.gif)

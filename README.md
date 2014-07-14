fuse-jpeg-preview
=================

virtual filesystem containing all preview images or thumbnails of a source filesystem - using Fuse / Perl

motivation
----------

- I have a digital camera making pictures with a size of up to 10MB each (6000x4000 pixels).
- Sometimes I want to browse through a bunch of pictures using my old netbook which has a display of 1024x600 and is quite slow.
- I found that the metadata of the images (EXIF) contains preview images of 1616x1080

solution
--------

- This virtual filesystem clones the structure of a source filesystem containing jpeg files, but only passes the preview images through.
- File attributes (file size) are dynamically replaced by the size of the preview picture of the image.
- You can use any application to open and display the preview images of the destination filesystem.
- Less data needs to be read and processed/scaled and so displaying images is much faster.

dependencies
------------

- libfuse-perl
- libimage-exiftool-perl

usage
-----

call the script using
```
./fuse-jpeg-preview.pl src dst
```

the images in the directory 'src' now show up in the directory 'dst' containing only the small preview images:
```
$ ls -sh1 src
total 20M
9,5M 00451.jpg
9,8M 00452.jpg

$ exiftool -ImageSize src/00451.jpg 
Image Size                      : 6000x4000

$ ls -sh1 dst
total 1,6M
777K 00451.jpg
837K 00452.jpg

$ exiftool -ImageSize dst/00451.jpg 
Image Size                      : 1616x1080
```

to unmount, use:
```
fusermount -u dst
```

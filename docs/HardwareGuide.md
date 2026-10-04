# Hardware Requirements

## Computer
**RAM:** 4GB absolute minimum (tight), 8GB comfortable. 
**CPU:** Any modern x86-64 will work. 
**GPU:** No dedicated GPU needed. An integrated GPU is beneficial but not required if you can ensure direct play or are okay with limited transcoding capacity. For hardware-accelerated transcoding you want an Intel 6th gen+ iGPU (QuickSync) or a Ryzen G-series APU.

Direct play means your clients natively support the video format. This is variable depending on device (e.g. Smart TV, PS5, Windows, etc.), but the most supported format is H.264 video with AAC audio in an MP4.

**Storage:** A small SSD is recommended for the OS, while slower hard drives are ok for data storage. Drives should roughly be the same capacity - the parity drive for SnapRAID needs to be as big as the biggest drive in the array.

The best drives are the ones you already have! But if you are buying new drives, look for CMR/PMR rather than SMR.

**Form Factor:** It can be nice to have the server take up a small footprint. I recommend finding a Mini-ITX motherboard (not ATX). Keep in mind power supply (PSU) form factor as well. Some cases require FlexATX or SFX/SFX-L, rather than Full-ATX. A smaller footprint case might also require a smaller form factor CPU cooler, or smaller case fans. 

You can 3D print a case for relatively cheap. I recommend one of these:
- https://www.printables.com/model/714333-modular-4-12-bay-nas-itx-case-modcase-mass
- https://www.printables.com/model/847728-rnas-6x-a-completely-3d-printable-and-toolless-pc

That being said, there's nothing wrong with running inside whatever desktop case you have lying around.

## Other
- A USB flash drive (8GB+) for the OMV installer
- Ethernet cable (wired connection strongly recommended for a server)

#!/usr/bin/env perl
# listing.pl

use strict;
use warnings;

use Fuse;
use Image::ExifTool qw(ImageInfo);
use POSIX qw(ENOENT EISDIR EINVAL O_WRONLY);

# read arguments
my ( $source, $mount ) = @ARGV if @ARGV;
( $source && $mount ) or die "Usage: ", $0, " <source> <mount>", "\n";

# cache for filesize
my %size_cache;

sub path_to_ref {
    my $path = shift;
    $path =~ s#^/##;
	return "$source/$path";
}

# read directory contents
sub getdir {
	my $path = path_to_ref(shift);

	return -ENOENT() unless (-d "$path"); 

	opendir(DIR, "$path");
	my @dir = readdir(DIR);
	close DIR;

    return (@dir, 0);
}

# get attributes of a file
sub getattr {
    my $path = path_to_ref(shift);

	return -ENOENT() unless (-e "$path");

    my $context = Fuse::fuse_get_context();

	my @stat = stat($path);
	#   0 dev      device number of filesystem
	#   1 ino      inode number
	#   2 mode     file mode  (type and permissions)
	#   3 nlink    number of (hard) links to the file
	#   4 uid      numeric user ID of file's owner
	#   5 gid      numeric group ID of file's owner
	#   6 rdev     the device identifier (special files only)
	#   7 size     total size of file, in bytes
	#   8 atime    last access time in seconds since the epoch
	#   9 mtime    last modify time in seconds since the epoch
	#  10 ctime    inode change time in seconds since the epoch
	#  11 blksize  preferred block size for file system I/O
	#  12 blocks   actual number of blocks allocated

    my $size = 0;

	my $typemode;
	if (-d "$path")
	{
		$typemode = 0040500;
	}
	else
	{
		$typemode = 0100400;

		# for jpgs, fetch the size of the preview/thumbnail
		$size = jpg_get_dynamic_size($path);
		
		if ($size < 0)
		{
			# use original file size
			$size = -s $path;
			printf "attr %s // %d (%d)\n", $path, $size, $context->{pid};
		}
		else
		{
			printf "attr %s %d (%d)\n", $path, $size, $context->{pid};
		}
	}

    my $uid   = $context->{uid};
    my $gid   = $context->{gid};
    #my $uid   = $stat[4];
    #my $gid   = $stat[5];

    my $atime = $stat[8];
	my $mtime = $stat[9];
	my $ctime = $stat[10];

    #my ( $dev, $ino, $rdev, $blocks, $nlink, $blksize ) = ( 0, 0, 0, 1, 1, 1024 );
    my ( $dev, $ino, $rdev, $blocks, $nlink, $blksize ) = ( 0, 0, 0, int($size/512), 1, 1024 );

    return (
        $dev,  $ino,   $typemode,  $nlink, $uid,     $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks
    );

}

# check jpg file extension
sub is_jpg {
	my $path = shift;
	return 1 if ($path =~ /\.[Jj][Pp][Ee]?[Gg]$/);
	return 0;
}

# get size of preview/thumbnail image of a jpg file
sub jpg_get_dynamic_size {
	my $path = shift;

	if (is_jpg($path))
	{
		# use cached value when set
		return $size_cache{$path} if ($size_cache{$path});
		my $size = -1;

		# get exif information for preview and thumbnail image size
		my %info = %{ImageInfo($path, qw(MPImageLength ThumbnailLength), {'FastScan' => '1'})};

		if ($info{'MPImageLength'})
		{
			$size = $info{'MPImageLength'};
		}
		elsif ($info{'ThumbnailLength'})
		{
			$size = $info{'ThumbnailLength'} # + 100;
		}

		$size_cache{$path} = $size;
		return $size;
	}

	return -1;
}

# read and return the preview/thumbnail image of a jpg file
sub jpg_get_preview {
	my $path = shift;

	my $buffer;
	my $size;
	my $orientation;

	# get exif data
	my %info = %{ImageInfo($path, qw(MPImageLength ThumbnailLength PreviewImage ThumbnailImage Orientation Rotation), {'FastScan' => '1'})};

	if ($info{'MPImageLength'})
	{
		$size = $info{'MPImageLength'};
		$buffer = ${$info{'PreviewImage'}};

		printf ("\nPI: %d %d", $size, length($buffer));
	}
	elsif ($info{'ThumbnailLength'})
	{
		$size = $info{'ThumbnailLength'};
		$buffer = ${$info{'ThumbnailImage'}};

		printf ("\nTN: %d %d", $size, length($buffer));

		print "\n";
		return $buffer;

	}
	else
	{
		return -1
	}

	# set exif orientation & rotation flag in preview/thumbnail image
	# (this might change the image size)

	if ($info{'Orientation'})
	{
		my $size0 = length($buffer);

		my $exifTool = new Image::ExifTool;
		$exifTool->SetNewValue(Orientation => $info{'Orientation'});
		$exifTool->WriteInfo(\$buffer);

		my $size1 = length($buffer);

		printf ("\nO: %s - %d %d %d", $info{'Orientation'}, $size0, $size1, $size1 - $size0);

	}

	if ($info{'Rotation'})
	{
		my $size0 = length($buffer);

		my $exifTool = new Image::ExifTool;
		$exifTool->SetNewValue(Rotation => $info{'Orientation'});
		$exifTool->WriteInfo(\$buffer);

		my $size1 = length($buffer);

		printf ("\nR: %s - %d %d %d", $info{'Rotation'}, $size0, $size1, $size1 - $size0);

	}

	print "\n";
	return $buffer;

}

# open a file returning a file handle
sub file_open {
	my $path = path_to_ref(shift);

	print "open $path";

	return -ENOENT() unless (-e $path);
	return -EISDIR() unless (-f $path);

	if (jpg_get_dynamic_size($path) > 0)
	{
		# for jpg files we turn the scalar containing the preview image into a file handle

		my $buffer_open = jpg_get_preview($path);

		if ($buffer_open)
		{
			open my $fh, "<", \$buffer_open;
			binmode $fh;
			return 0, $fh;
		}

		print " -\n";
		return -1;

	}
	else
	{
		# for other files we just use a normal file handle

		print " //\n";

		open my $fh, "<", $path;
		binmode $fh;
		return 0, $fh
	}

}

# read some data from the filehandle (no matter if it is a real one or uses a scalar)
sub file_read {

	my $path = path_to_ref(shift);
    my ( $bytes, $offset, $fh ) = @_;
	
	printf ("read %s %d (%d-%d)\n", $path, $bytes, $offset, $offset + $bytes - 1);

	my $buffer = undef;

	seek($fh, $offset, 0);
	my $status = read( $fh, $buffer, $bytes );

    if ($status > 0) {
        return $buffer;
    }
    return $status;

}

# release file handle
sub file_release {
	my $path = path_to_ref(shift);
    my ($flags, $fh) = @_;

	print "close $path\n";

    close($fh);
}

Fuse::main(
    mountpoint  => "$mount",
    getdir      => \&getdir,
    getattr     => \&getattr,
    open        => \&file_open,
    read        => \&file_read,
    release     => \&file_release,
    threaded    => 0
);

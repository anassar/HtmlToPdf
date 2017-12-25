#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use HTML::TreeBuilder 5 -weak; # Ensure weak references in use
use File::Copy;

# USAGE:
# mkdir ~/UE4Docs
# perl ~/workspace/ue4DocsToPdf.pl

my $docsDirName  = 'UE4Docs';
my $docsDirPath  = '/home/anassar/' . $docsDirName;
my $listFilePath = '/home/anassar/workspace/UE4Docs.txt';
my $baseURL      = 'https://docs.unrealengine.com';
my $bookTitle    = 'UnrealEngine4Documentation';
my $maxDepth     = -1;
my $ParseHtml    =  1;
my $startAtTitle = undef; # "Basic How To's"; # Title of node to start building.


if ($ParseHtml) {
	my $treeRoot = HTML::TreeBuilder->new_from_file( $listFilePath );
	$treeRoot->elementify();
	my $rootList = getRootList( \$treeRoot );
	if ( not defined $rootList )
	{
		die "*** Couldn't find the root list.";
	}
	my $topDir = getPath($bookTitle, $docsDirPath, '', '');
	if ( not -d $topDir ) {
		mkdir $topDir;
	}
	processList( $rootList, $bookTitle, $topDir, '', 0, (not defined $startAtTitle) );
}






#===--------------------------------------------------===#
#               S U B R O U T I N E S
#===--------------------------------------------------===#

sub getRootList {
	my ($elemRef) = @_;
	unless ( ref $$elemRef ) {
		return undef;
	}
	my $tag = $$elemRef->tag();
	#print "-- getRootList($tag)\n";
	if ( $tag eq 'ul' ) {
		return $$elemRef;
	}
	my @contents = $$elemRef->content_refs_list;
	foreach my $childElemRef ( @contents ) {
		my $list = getRootList( $childElemRef );
		return $list if (defined $list);
	}
	return undef;
}



sub processList {
	my ($list, $title, $currDir, $index, $depth, $selected) = @_;
	return unless ( ($maxDepth < 0) or ( $depth <= $maxDepth ) );
	print "-- Processing list: $index $title ($currDir)\n";

	my $count = 1;
	my @contents = $list->content_refs_list;
	foreach my $listItemRef ( @contents ) {
		my $tag = $$listItemRef->tag();
		if ( $tag ne 'li' ) {
			print Dumper($$listItemRef);
			die "*** Children of ul must be li: Found ($tag) at depth ($depth)";
		}
		processListItem( $$listItemRef, $currDir, getSubIndex( $index, $count ), $depth+1, $selected );
		$count = $count + 1;
	}
}

sub getSubIndex {
	my ($index, $count) = @_;
	if ( $index eq '' ) {
		return "$count";
	} else {
		return "$index.$count";
	}
}

sub processListItem {
	my ($listItem, $parentDir, $index, $depth, $selected) = @_;
	print "-- Processing list item: $index ($parentDir)\n";

	my @contents = $listItem->content_refs_list;
	if ( ( scalar( @contents ) < 1 ) or ( scalar( @contents ) > 2 ) ) {
		die "*** A list item must have at least one (and at most two) child element(s).";
	}

	my $paragraphElemRef = $contents[0];
	my ($url, $title) = processParagraphItem( $$paragraphElemRef );

	if ( not $selected ) {
		if ( not defined $startAtTitle ) {
			die "*** startAtTitle cannot be undefined while searching an unselected tree.\n";
		} elsif ( $title eq $startAtTitle ) {
			$selected = 1;
		}
	}

	my $isDeep = ( scalar( @contents ) > 1 );
	$title     =~ s/^\s+//;  # Remove leading  whitespace.
	$title     =~ s/\s+$//;  # Remove trailing whitespace.
	$title     =~ s/\s+/_/g; # Replace whitespace with underscores.
	$title     =~ s/[&]/and/g; # Replace ampersand with "and".
	$title     =~ s/^(\s*\d+\s*-\s*)/and/g; # Replace section numbering.
	$title     =~ s/'//g; # Replace apostrophes.
	$title     =~ s/\(/_/g; # Replace parentheses.
	$title     =~ s/\)/_/g; # Replace parentheses.
	$title     =~ s/\//_/g; # Replace slashes.
	my $currDir = undef;
	if ($isDeep) {
		$currDir = getPath($title, $parentDir, $index, '');
		if ( not -d $currDir ) {
			mkdir $currDir;
		}
	} else {
		$currDir = $parentDir;
	}
	if ( $selected ) {
		my $fpath = getPath($title, $currDir, $index, '.pdf');
		if ( not -f $fpath ) { # Convert files that haven't been converted on previous runs.
			convertUrlToPdf($url, $fpath);
		}
	}
	if ( $isDeep ) {
		my $sublistRef = $contents[1];
		my $tag = $$sublistRef->tag();
		if ( $tag ne 'ul' ) {
			die "A list item with 2 sub-items can only have ul as second item.\n\tFound $tag.";
		}
		processList( $$sublistRef, $title, $currDir, $index, $depth+1, $selected );
	}
}


sub processParagraphItem {
	my ($paragraphItem ) = @_;
	my $tag = $paragraphItem->tag();
	if ( $tag ne 'p' ) {
		die "Expected a <p> tag. Found <$tag>.";
	}
	my @contents = $paragraphItem->content_refs_list;
	if ( scalar( @contents ) != 1 ) {
		die "*** A paragraph item must have only one sub-item.";
	}
	my $hyperlinkItemRef = $contents[0];
	return processHyperlinkItem( $$hyperlinkItemRef );
}


sub processHyperlinkItem {
	my ( $hyperlinkItem ) = @_;
	my $tag = $hyperlinkItem->tag();
	if ( $tag ne 'a' ) {
		die "Expected a <a> tag. Found <$tag>.";
	}
	my @contents = $hyperlinkItem->content_refs_list;
	if ( scalar( @contents ) != 1 ) {
		die "*** A hyperlink item must have only one sub-item.";
	}
	my $spanItemRef = $contents[0];
	my $title = processSpanItem( $$spanItemRef );
	my %attributes = $hyperlinkItem->all_attr();
	if ( not exists $attributes{'href'} ) {
		die "*** A hyperlink item must have href attributes.";
	}
	my $url = "$baseURL" . $attributes{'href'};
	return ($url, $title);
}

sub processSpanItem {
	my ( $spanItem ) = @_;
	my $tag = $spanItem->tag();
	if ( $tag ne 'span' ) {
		die "Expected a <span> tag. Found <$tag>.";
	}
	my @contents = $spanItem->content_refs_list;
	if ( scalar( @contents ) != 1 ) {
		die "*** A span item must have only one sub-item.";
	}
	my $childElemRef = $contents[0];
	if ( ref $$childElemRef ) {
		#print Dumper($$hyperlinkRef);
		die "*** A span item must have only one sub-item of string type.";
	}
	return $$childElemRef;
}


sub getPath {
	my ($title, $parentDir, $index, $ext) = @_;

	$parentDir =~ s/\/+$//;  # Remove trailing /.
	$title     =~ s/^\s+//;  # Remove leading  whitespace.
	$title     =~ s/\s+$//;  # Remove trailing whitespace.
	$title     =~ s/\s+/_/g; # Replace whitespace with underscores.
	my $path = "$parentDir/${index}";
	if ( $index ne '' ) {
		$path .= "_";
	}
	$path .= "$title" . "$ext";
	return $path;
}


sub convertUrlToPdf {
	my ($url, $fpath) = @_;
	my $cmdName  = 'wkhtmltopdf';
	print "== Generating $fpath ($url)\n";
	system( "$cmdName $url $fpath" );
}






__END__


my $dstDirPath   = '/home/anassar/UE4Docs';

mkdir $dstDirPath;
my $count = 0;
combinePDFs( $docsDirPath, $docsDirName, $dstDirPath, \$count );


sub combinePDFs {
	my ( $srcDirPath, $srcDirName, $dstDirPath, $countRef ) = @_;
	my @inpfiles = getAllFiles( $srcDirPath );
	my @outfiles = ();
	foreach my $file ( sort @inpfiles ) {
		next if ( $file =~ m/^\s*[.]+\s*$/ );
		my $path = "$srcDirPath/$file";
		if ( -d $path ) {
			my $newDstDirPath = "$dstDirPath/$file";
			mkdir $newDstDirPath;
			my $newFile = combinePDFs( $path, $file, $newDstDirPath, $countRef );
			if ( defined $newFile ) {
				push @outfiles, $newFile;
			}
		} else {
			my $newPath = $path;
			$newPath =~ s/\s+/_/g; # Replace whitespace with underscores.
			rename( $path, $newPath );
			push @outfiles, $newPath;
		}
	}
	if ( scalar( @outfiles ) > 0 ) {
		my $ofpath = "$dstDirPath/$srcDirName.pdf";
		my $cmd = "gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=$ofpath \\\n" . join( " \\\n", @outfiles );
		print "========== Executing:\n\t$cmd\n\n";
		my $ret = system( $cmd );
		if ( $ret != 0 ) {
			exit( $ret );
		}
		$$countRef = $$countRef + 1;
		print "------ Combination count: $$countRef\n";
		return $ofpath;
	}
	return undef;
}



sub getAllFiles {
	my ( $dPath ) = @_;
	opendir( my $dh, $dPath) or die "*** Cannot open $dPath:\n$!\n";
	my @files = readdir $dh;
	closedir $dh;
	return @files;
}



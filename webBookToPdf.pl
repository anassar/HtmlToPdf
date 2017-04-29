#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use HTML::TreeBuilder 5 -weak; # Ensure weak references in use
use File::Copy;

# USAGE:
# mkdir ~/DesigningAndBuildingParallelPrograms
# perl ~/workspace/webBookToPdf.pl

my $baseURL      = 'http://www.mcs.anl.gov/~itf/dbpp/text/';
my $docsDir      = '/home/anassar/DesigningAndBuildingParallelPrograms';
my $dstDirPath   = '/home/anassar/DesigningAndBuildingParallelPrograms_';
my $listFilePath = '/home/anassar/workspace/DesigningAndBuildingParallelPrograms.txt';
my $srcDirName   = 'DesigningAndBuildingParallelPrograms';
my $bookTitle    = 'Designing and Building Parallel Programs';
my $maxDepth     = -1;
my $ParseHtml    =  0;



if ($ParseHtml)
{
	my $treeRoot = HTML::TreeBuilder->new_from_file( $listFilePath );
	$treeRoot->elementify();
	my $rootList = getRootList( \$treeRoot );
	if ( not defined $rootList )
	{
		die "*** Couldn't find the root list.";
	}
	my $topDir = getPath($bookTitle, $docsDir, '', '');
	mkdir $topDir;
	processList( $rootList, $bookTitle, $topDir, '', 0 );
}




mkdir $dstDirPath;
my $count = 0;
combinePDFs( $docsDir, $srcDirName, $dstDirPath, \$count );




#===--------------------------------------------------===#
#               S U B R O U T I N E S
#===--------------------------------------------------===#

sub getRootList {
	my ($elemRef) = @_;
	unless ( ref $$elemRef ) {
		return;
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
	my ($list, $title, $currDir, $index, $depth) = @_;
	return unless ( ($maxDepth < 0) or ( $depth <= $maxDepth ) );
	print "-- Processing list: $index $title ($currDir)\n";

	my $count = 1;
	my @contents = $list->content_refs_list;
	foreach my $listItemRef ( @contents ) {
		my $tag = $$listItemRef->tag();
		if ( $tag ne 'li' ) {
			#print Dumper($$listItemRef);
			die "*** Children of ul must be li: Found ($tag) at depth ($depth)";
		}
		processListItem( $$listItemRef, $currDir, getSubIndex( $index, $count ), $depth+1 );
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
	my ($listItem, $parentDir, $index, $depth) = @_;
	print "-- Processing list item: $index ($parentDir)\n";

	my @contents = $listItem->content_refs_list;
	if ( ( scalar( @contents ) < 1 ) or ( scalar( @contents ) > 2 ) ) {
		die "*** A list item must have at least one (and at most two) child element(s).";
	}

	my $hyperlinkRef = $contents[0];
	my $tag = $$hyperlinkRef->tag();
	if ( $tag ne 'a' ) {
		die "*** A list item with a single child element must be a hyperlink (Found $tag).";
	}

	my $isDeep = ( scalar( @contents ) > 1 );
	my ($currDir, $title) = processHyperlink( $$hyperlinkRef, $parentDir, $index, $isDeep );

	if ( not $isDeep ) {
		return;
	}

	my $sublistRef = $contents[1];
	$tag = $$sublistRef->tag();
	if ( $tag ne 'ul' ) {
		die "A list item with 2 sub-items can only have ul as second item.\n\tFound $tag.";
	}
	processList( $$sublistRef, $title, $currDir, $index, $depth+1 );
}


sub processHyperlink {
	my ($hyperlinkItem, $parentDir, $index, $isDeep) = @_;
	my @contents = $hyperlinkItem->content_refs_list;
	if ( scalar( @contents ) != 1 ) {
		die "*** A hyperlink item must have only one sub-item.";
	}
	my $childElemRef = $contents[0];
	if ( ref $$childElemRef ) {
		#print Dumper($$childElemRef);
		die "*** A hyperlink item must have only one sub-item of string type.";
	}
	my $title = $$childElemRef;
	$title     =~ s/^\s+//;  # Remove leading  whitespace.
	$title     =~ s/\s+$//;  # Remove trailing whitespace.
	$title     =~ s/\s+/_/g; # Replace whitespace with underscores.
	my %attributes = $hyperlinkItem->all_attr();
	if ( not exists $attributes{'href'} ) {
		die "*** A hyperlink item must have href attributes.";
	}
	my $url = "$baseURL" . $attributes{'href'};

	my $currDir = undef;
	if ($isDeep) {
		$currDir = getPath($title, $parentDir, $index, '');
		mkdir $currDir;
	} else {
		$currDir = $parentDir;
	}
	my $fpath = getPath($title, $currDir, $index, '.pdf');
	convertUrlToPdf($url, $fpath);
	return ($currDir, $title);
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

sub getTitle {
	my ($hyperlinkItem) = @_;
	my @contents = $hyperlinkItem->content_refs_list;
	if ( scalar( @contents ) != 1 ) {
		die "*** A hyperlink item must have only one text sub-item.";
	}
	my $childElemRef = $contents[0];
	unless ( ref $$childElemRef ) {
		return $$childElemRef;
	}
	die "*** A <a> item can only have a text sub-item.";
}



sub convertUrlToPdf {
	my ($url, $fpath) = @_;
	my $cmdName  = '/home/anassar/wkhtmltox/bin/wkhtmltopdf';
	print "== Generating $fpath ($url)\n";
	system( "$cmdName $url $fpath" );
}


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




__END__



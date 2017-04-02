#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use HTML::TreeBuilder 5 -weak; # Ensure weak references in use


# USAGE:
# cd ~/TensorFlowPdfDocs
# perl ../workspace/tensorFlowDocsToPdf.pl

my $baseURL  = 'https://www.tensorflow.org/api_docs';
my $docsDir  = '/home/anassar/TensorFlowPdfDocs';

my $maxDepth = 20;

my $CombineFilesOnly = 1;

if (not $CombineFilesOnly) {
	my $treeRoot = HTML::TreeBuilder->new_from_url($baseURL);
	$treeRoot->elementify();

	my $maxSize = 0;
	my $largestList = undef;
	getLargestListRoot( \$treeRoot, 0, 0, \$maxSize, \$largestList );
	if ( not defined $largestList ) {
		die "*** Couldn't find the list root.";
	}
	processList( $largestList, 'Tensor Flow API r1.0 Documentation', $docsDir, '' );
}

my $dstDirPath = '/home/anassar/TensorFlowPdfDocs_';
mkdir $dstDirPath;
my $count = 0;
combinePDFs( $docsDir, 'TensorFlowPdfDocs', $dstDirPath, \$count );



sub combinePDFs {
	my ( $srcDirPath, $srcDirName, $dstDirPath, $countRef ) = @_;
	my @inpfiles = getAllFiles( $srcDirPath );
	my @outfiles = ();
	foreach my $file ( sort @inpfiles ) {
		my $path = "$srcDirPath/$file";
		if ( $file =~ m/^\s*[.]+\s*$/ ) {
		} elsif ( -d $path ) {
			my $newDstDirPath = "$dstDirPath/$file";
			mkdir $newDstDirPath;
			my $newFile = combinePDFs( $path, $file, $newDstDirPath, $countRef );
			if ( defined $newFile ) {
				push @outfiles, $newFile;
			}
		} else {
			push @outfiles, $path;
		}
	}
	if ( scalar( @outfiles ) ) {
		my $ofpath = "$dstDirPath/$srcDirName.pdf";
		my $cmd = "gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=$ofpath " . join( ' ', @outfiles );
		#print "========== Executing:\n\t$cmd\n\n";
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


#===--------------------------------------------------===#
#               S U B R O U T I N E S
#===--------------------------------------------------===#

sub getLargestListRoot {
	my ($elemRef, $foundBody, $depth, $maxSizeRef, $largestListRef) = @_;
	unless ( ref $$elemRef ) {
		return;
	}
	my $tag = $$elemRef->tag();
	if ( $tag eq 'body' ) {
		$foundBody = 1;
	}
	if ( $foundBody and ($tag eq 'ul') ) {
		my $size = 0;
		getListTreeSize( $elemRef, \$size );
		print "==== Found a potential ul at depth = $depth, size = $size\n";
		if ($size > $$maxSizeRef) {
			$$maxSizeRef     = $size;
			$$largestListRef = $$elemRef;
		}
		return;
	}
	my @contents = $$elemRef->content_refs_list;
	foreach my $childElemRef ( @contents ) {
		getLargestListRoot( $childElemRef, $foundBody, $depth+1, $maxSizeRef, $largestListRef );
	}
}


sub getListTreeSize {
	my ($elemRef, $sizeRef) = @_;
	$$sizeRef += 1;
	unless ( ref $$elemRef ) {
		return;
	}
	my @contents = $$elemRef->content_refs_list;
	foreach my $childElemRef ( @contents ) {
		getListTreeSize( $childElemRef, $sizeRef );
	}
}



sub processList {
	my ($list, $title, $parentDir, $index) = @_;
	print "-- Processing list: $index.$title ($parentDir)\n";
	$parentDir =~ s/\/$//;   # Remove trailing /.
	$title     =~ s/\s+/_/g; # Replace whitespace with underscores.
	my $currDir = "$parentDir/${index}";
	if ( $index ne '' ) {
		$currDir .= "_";
	}
	$currDir .= "$title";
	mkdir $currDir;
	my $count = 1;
	my @contents = $list->content_refs_list;
	foreach my $listItemRef ( @contents ) {
		my $tag = $$listItemRef->tag();
		if ( $tag ne 'li' ) {
			die "*** Children of ul must be li.";
		}
		processListItem( $$listItemRef, $currDir, getSubIndex( $index, $count ) );
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
	my ($listItem, $parentDir, $index) = @_;
	print "-- Processing list item: $index ($parentDir)\n";
	my @contents = $listItem->content_refs_list;
	if ( scalar( @contents ) == 1 ) {
		my $childElemRef = $contents[0];
		my $tag = $$childElemRef->tag();
		if ( ($tag ne 'a') and ($tag ne 'hr') ) {
			die "*** A list item with a single child element must be a hyperlink (Found $tag).";
		}
		if ( $tag eq 'a' ) {
			processHyperlink( $$childElemRef, $parentDir, $index );
		}
		return;
	}
	if ( scalar( @contents ) != 3 ) {
		die "*** A list item which is not a hyperlink must contain 3 items: span/local hyperlink/ul.";
	}
	my $title   = undef;
	my $subList = undef;
	for my $childElemRef ( @contents ) {
		my $tag = $$childElemRef->tag();
		if ( $tag eq 'span' ) {
			$title = getTitle( $$childElemRef );
		} elsif ( $tag eq 'a' ) {
			checkLocalHyperlink( $$childElemRef );
		} elsif ( $tag eq 'ul' ) {
			$subList = $$childElemRef;
		} else {
			die "A list item with 3 sub-items can only contain span/hyperlink/ul.\n\tFound $tag.";
		}
	}
	if ( not defined $title ) {
		die "*** A list item with no title found.";
	}
	if ( not defined $subList ) {
		die "*** A list item with no sub-list found.";
	}
	processList( $subList, $title, $parentDir, $index );
}


sub processHyperlink {
	my ($hyperlinkItem, $parentDir, $index) = @_;
	my @contents = $hyperlinkItem->content_refs_list;
	if ( scalar( @contents ) != 1 ) {
		die "*** A hyperlink item must have only one sub-item.";
	}
	my $childElemRef = $contents[0];
#	unless ( ref $$childElemRef ) {
#		print Dumper($$childElemRef);
#		die "*** A hyperlink item must have only one sub-item of ref type.";
#	}
#	my $tag = $$childElemRef->tag();
#	if ( $tag ne 'span' ) {
#		die "*** A hyperlink item must have only one sub-item of <span> type.";
#	}
#	my $title = getTitle( $$childElemRef );
	if ( ref $$childElemRef ) {
		#print Dumper($$childElemRef);
		die "*** A hyperlink item must have only one sub-item of string type.";
	}
	my $title = $$childElemRef;
	my %attributes = $hyperlinkItem->all_attr();
	if ( not exists $attributes{'href'} ) {
		die "*** A hyperlink item must have href attributes.";
	}
	my $url = $attributes{'href'};
	$parentDir =~ s/\/$//;   # Remove trailing /.
	$title     =~ s/\s+/_/g; # Replace whitespace with underscores.
	my $fpath  = "$parentDir/${index}_$title.pdf";
	convertUrlToPdf($url, $fpath);
}

sub getTitle {
	my ($spanItem) = @_;
	my @contents = $spanItem->content_refs_list;
	if ( scalar( @contents ) != 1 ) {
		die "*** A title span item must have only one sub-item.";
	}
	my $childElemRef = $contents[0];
	unless ( ref $$childElemRef ) {
		return $$childElemRef;
	}
	my $tag = $$childElemRef->tag();
	if ( $tag ne 'span' ) {
		die "*** A <span> can only have a <span> or text sub-item.";
	}
	return getTitle( $$childElemRef );
}

sub checkLocalHyperlink {
	my ($hyperlinkItem) = @_;
	my @contents = $hyperlinkItem->content_refs_list;
	if ( scalar( @contents ) > 1 ) {
		print "*** A local hyperlink has " . scalar( @contents ) . " sub-items.\n";
		die "*** A local hyperlink must have only text content.";
	}
}


sub convertUrlToPdf {
	my ($url, $fpath) = @_;
	my $cmdName  = '/home/anassar/wkhtmltox/bin/wkhtmltopdf';
	print "== Generating $fpath ($url)\n";
	system( "$cmdName $url $fpath" );
}



sub getAllFiles {
	my ( $dPath ) = @_;
	opendir( my $dh, $dPath) or die "*** Cannot open $dPath:\n$!\n";
	my @files = readdir $dh;
	closedir $dh;
	return @files;
}









__END__

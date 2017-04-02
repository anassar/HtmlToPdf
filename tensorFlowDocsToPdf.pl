#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use HTML::TreeBuilder 5 -weak; # Ensure weak references in use
use File::Copy;

# USAGE:
# cd ~/TensorFlowPdfDocs
# perl ../workspace/tensorFlowDocsToPdf.pl

my $baseURL  = 'https://www.tensorflow.org/api_docs';
my $docsDir  = '/home/anassar/TensorFlowPdfDocs/';


my $ParseHtml = 0;

if ($ParseHtml) {
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



my $devDocs = getDeveloperDocs();
processDevDocsList( $devDocs, $docsDir, '' );


my $dstDirPath = '/home/anassar/TensorFlowPdfDocs_';
mkdir $dstDirPath;
my $count = 0;
combinePDFs( $docsDir, 'TensorFlowDeveloperDoc', $dstDirPath, \$count );




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
			my $newPath = $path;
			$newPath =~ s/\s+/_/g; # Replace whitespace with underscores.
			rename( $path, $newPath );
			push @outfiles, $newPath;
		}
	}
	if ( scalar( @outfiles ) ) {
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



sub processDevDocsList {
	my ($list, $parentDir, $index) = @_;
	my $title = $list->{title};
	print "-- Processing list: $index.$title ($parentDir)\n";
	$parentDir =~ s/\/$//;   # Remove trailing /.
	$title     =~ s/\s+/_/g; # Replace whitespace with underscores.
	if (exists $list->{contents}) {
		my $currDir = "$parentDir/${index}";
		if ( $index ne '' ) {
			$currDir .= "_";
		}
		$currDir .= "$title";
		mkdir $currDir;
		my $count = 1;
		foreach my $listItem ( @{ $list->{contents} } ) {
			processDevDocsList( $listItem, $currDir, getSubIndex( $index, $count ) );
			$count = $count + 1;
		}
	} elsif (exists $list->{url}) {
		my $url = $list->{url};
		my $fpath  = "$parentDir/${index}_$title.pdf";
		convertUrlToPdf($url, $fpath);
	} else {
		die "*** Unrecognized DevDocsList structure.";
	}
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



sub getDeveloperDocs {
	return { title => 'TensorFlowDeveloperDocs', contents => [
	{ title => 'Get_Started', contents => [
	{title => 'Getting_Started_With_TensorFlow'                    , url => 'https://www.tensorflow.org/get_started/get_started'},
	{title => 'MNIST For ML Beginners'                             , url => 'https://www.tensorflow.org/get_started/mnist/beginners'},
	{title => 'Deep MNIST for Experts'                             , url => 'https://www.tensorflow.org/get_started/mnist/pros'},
	{title => 'TensorFlow Mechanics 101'                           , url => 'https://www.tensorflow.org/get_started/mnist/mechanics'},
	{title => 'tf.contrib.learn Quickstart'                        , url => 'https://www.tensorflow.org/get_started/tflearn'},
	{title => 'Building Input Functions with tf.contrib.learn'     , url => 'https://www.tensorflow.org/get_started/input_fn'},
	{title => 'TensorBoard_Visualizing Learning'                   , url => 'https://www.tensorflow.org/get_started/summaries_and_tensorboard'},
	{title => 'TensorBoard_Embedding Visualization'                , url => 'https://www.tensorflow.org/get_started/embedding_viz'},
	{title => 'TensorBoard_Graph Visualization'                    , url => 'https://www.tensorflow.org/get_started/graph_viz'},
	{title => 'Logging and Monitoring Basics with tf.contrib.learn', url => 'https://www.tensorflow.org/get_started/monitors'},
	]},
	{ title => 'Programmers_Guide', contents => [
	{ title => 'Reading data'                                                   , url => 'https://www.tensorflow.org/programmers_guide/reading_data'},
	{ title => 'Threading and Queues'                                           , url => 'https://www.tensorflow.org/programmers_guide/threading_and_queues'},
	{ title => 'Sharing Variables'                                              , url => 'https://www.tensorflow.org/programmers_guide/variable_scope'},
	{ title => 'TensorFlow Version Semantics'                                   , url => 'https://www.tensorflow.org/programmers_guide/version_semantics'},
	{ title => 'TensorFlow Data Versioning_GraphDefs and Checkpoints'           , url => 'https://www.tensorflow.org/programmers_guide/data_versions'},
	{ title => 'Supervisor_Training Helper for Days-Long Trainings'             , url => 'https://www.tensorflow.org/programmers_guide/supervisor'},
	{ title => 'TensorFlow Debugger_tfdbg_Command-Line-Interface Tutorial_MNIST', url => 'https://www.tensorflow.org/programmers_guide/debugger'},
	{ title => 'How to Use TensorFlow Debugger_tfdbg_with tf.contrib.learn'     , url => 'https://www.tensorflow.org/programmers_guide/tfdbg-tflearn'},
	{ title => 'Exporting and Importing a MetaGraph'                            , url => 'https://www.tensorflow.org/programmers_guide/meta_graph'},
	{ title => 'Frequently Asked Questions'                                     , url => 'https://www.tensorflow.org/programmers_guide/faq'},
	{ title => 'Tensor Ranks, Shapes, and Types'                                , url => 'https://www.tensorflow.org/programmers_guide/dims_types'},
	{ title => 'Variables_Creation, Initialization, Saving, and Loading'        , url => 'https://www.tensorflow.org/programmers_guide/variables'},
	]},
	{ title => 'Tutorials', contents => [
	{title => 'Mandelbrot Set'                                              , url => 'https://www.tensorflow.org/tutorials/mandelbrot'},
	{title => 'Partial Differential Equations'                              , url => 'https://www.tensorflow.org/tutorials/pdes'},
	{title => 'Convolutional Neural Networks'                               , url => 'https://www.tensorflow.org/tutorials/deep_cnn'},
	{title => 'Image Recognition'                                           , url => 'https://www.tensorflow.org/tutorials/image_recognition'},
	{title => 'How to Retrain Inception_s Final Layer for New Categories'   , url => 'https://www.tensorflow.org/tutorials/image_retraining'},
	{title => 'Vector Representations of Words'                             , url => 'https://www.tensorflow.org/tutorials/word2vec'},
	{title => 'Recurrent Neural Networks'                                   , url => 'https://www.tensorflow.org/tutorials/recurrent'},
	{title => 'Sequence-to-Sequence Models'                                 , url => 'https://www.tensorflow.org/tutorials/seq2seq'},
	{title => 'A Guide to TF Layers_Building a Convolutional Neural Network', url => 'https://www.tensorflow.org/tutorials/layers'},
	{title => 'Large-scale Linear Models with TensorFlow'                   , url => 'https://www.tensorflow.org/tutorials/linear'},
	{title => 'TensorFlow Linear Model Tutorial'                            , url => 'https://www.tensorflow.org/tutorials/wide'},
	{title => 'TensorFlow Wide and Deep Learning Tutorial'                  , url => 'https://www.tensorflow.org/tutorials/wide_and_deep'},
	{title => 'Using GPUs'                                                  , url => 'https://www.tensorflow.org/tutorials/using_gpu'},
	]},
	{ title => 'Performance', contents => [
	    {title => 'Performance'                                    , url => 'https://www.tensorflow.org/performance/performance_guide'},
	    {title => 'XLA Overview'                                   , url => 'https://www.tensorflow.org/performance/xla/'},
	    {title => 'Broadcasting semantics'                         , url => 'https://www.tensorflow.org/performance/xla/broadcasting'},
	    {title => 'Developing a new backend for XLA'               , url => 'https://www.tensorflow.org/performance/xla/developing_new_backend'},
	    {title => 'Using JIT Compilation'                          , url => 'https://www.tensorflow.org/performance/xla/jit'},
	    {title => 'Operation Semantics'                            , url => 'https://www.tensorflow.org/performance/xla/operation_semantics'},
	    {title => 'Shapes and Layout'                              , url => 'https://www.tensorflow.org/performance/xla/shapes'},
	    {title => 'Using AOT compilation'                          , url => 'https://www.tensorflow.org/performance/xla/tfcompile'},
	    {title => 'How to Quantize Neural Networks with TensorFlow', url => 'https://www.tensorflow.org/performance/quantization'},
	]},
 	]};
}



__END__


#####################################################################
#
# The Perl::Tidy::Tokenizer package is essentially a filter which
# reads lines of perl source code from a source object and provides
# corresponding tokenized lines through its get_line() method.  Lines
# flow from the source_object to the caller like this:
#
# source_object --> LineBuffer_object --> Tokenizer -->  calling routine
#   get_line()         get_line()           get_line()     line_of_tokens
#
# The source object can be any object with a get_line() method which
# supplies one line (a character string) perl call.
# The LineBuffer object is created by the Tokenizer.
# The Tokenizer returns a reference to a data structure 'line_of_tokens'
# containing one tokenized line for each call to its get_line() method.
#
# WARNING: This is not a real class.  Only one tokenizer my be used.
#
########################################################################

package Perl::Tidy::Tokenizer;
use strict;
use warnings;
our $VERSION = '20211029.05';

# this can be turned on for extra checking during development
use constant DEVEL_MODE => 0;

use Perl::Tidy::LineBuffer;
use Carp;

# PACKAGE VARIABLES for processing an entire FILE.
# These must be package variables because most may get localized during
# processing.  Most are initialized in sub prepare_for_a_new_file.
use vars qw{
  $tokenizer_self

  $last_nonblank_token
  $last_nonblank_type
  $last_nonblank_block_type
  $statement_type
  $in_attribute_list
  $current_package
  $context

  %is_constant
  %is_user_function
  %user_function_prototype
  %is_block_function
  %is_block_list_function
  %saw_function_definition
  %saw_use_module

  $brace_depth
  $paren_depth
  $square_bracket_depth

  @current_depth
  @total_depth
  $total_depth
  $next_sequence_number
  @nesting_sequence_number
  @current_sequence_number
  @paren_type
  @paren_semicolon_count
  @paren_structural_type
  @brace_type
  @brace_structural_type
  @brace_context
  @brace_package
  @square_bracket_type
  @square_bracket_structural_type
  @depth_array
  @nested_ternary_flag
  @nested_statement_type
  @starting_line_of_current_depth
};

# GLOBAL CONSTANTS for routines in this package,
# Initialized in a BEGIN block.
use vars qw{
  %is_indirect_object_taker
  %is_block_operator
  %expecting_operator_token
  %expecting_operator_types
  %expecting_term_types
  %expecting_term_token
  %is_digraph
  %is_file_test_operator
  %is_trigraph
  %is_tetragraph
  %is_valid_token_type
  %is_keyword
  %is_code_block_token
  %is_sort_map_grep_eval_do
  %is_grep_alias
  %really_want_term
  @opening_brace_names
  @closing_brace_names
  %is_keyword_taking_list
  %is_keyword_taking_optional_arg
  %is_keyword_rejecting_slash_as_pattern_delimiter
  %is_keyword_rejecting_question_as_pattern_delimiter
  %is_q_qq_qw_qx_qr_s_y_tr_m
  %is_sub
  %is_package
  %is_comma_question_colon
  %other_line_endings
  $code_skipping_pattern_begin
  $code_skipping_pattern_end
};

# GLOBAL VARIABLES which are constant after being configured by user-supplied
# parameters.  They remain constant as a file is being processed.
my (

    $rOpts_code_skipping,
    $code_skipping_pattern_begin,
    $code_skipping_pattern_end,
);

# possible values of operator_expected()
use constant TERM     => -1;
use constant UNKNOWN  => 0;
use constant OPERATOR => 1;

# possible values of context
use constant SCALAR_CONTEXT  => -1;
use constant UNKNOWN_CONTEXT => 0;
use constant LIST_CONTEXT    => 1;

# Maximum number of little messages; probably need not be changed.
use constant MAX_NAG_MESSAGES => 6;

BEGIN {

    # Array index names for $self.
    # Do not combine with other BEGIN blocks (c101).
    my $i = 0;
    use constant {
        _rhere_target_list_                  => $i++,
        _in_here_doc_                        => $i++,
        _here_doc_target_                    => $i++,
        _here_quote_character_               => $i++,
        _in_data_                            => $i++,
        _in_end_                             => $i++,
        _in_format_                          => $i++,
        _in_error_                           => $i++,
        _in_pod_                             => $i++,
        _in_skipped_                         => $i++,
        _in_attribute_list_                  => $i++,
        _in_quote_                           => $i++,
        _quote_target_                       => $i++,
        _line_start_quote_                   => $i++,
        _starting_level_                     => $i++,
        _know_starting_level_                => $i++,
        _tabsize_                            => $i++,
        _indent_columns_                     => $i++,
        _look_for_hash_bang_                 => $i++,
        _trim_qw_                            => $i++,
        _continuation_indentation_           => $i++,
        _outdent_labels_                     => $i++,
        _last_line_number_                   => $i++,
        _saw_perl_dash_P_                    => $i++,
        _saw_perl_dash_w_                    => $i++,
        _saw_use_strict_                     => $i++,
        _saw_v_string_                       => $i++,
        _hit_bug_                            => $i++,
        _look_for_autoloader_                => $i++,
        _look_for_selfloader_                => $i++,
        _saw_autoloader_                     => $i++,
        _saw_selfloader_                     => $i++,
        _saw_hash_bang_                      => $i++,
        _saw_end_                            => $i++,
        _saw_data_                           => $i++,
        _saw_negative_indentation_           => $i++,
        _started_tokenizing_                 => $i++,
        _line_buffer_object_                 => $i++,
        _debugger_object_                    => $i++,
        _diagnostics_object_                 => $i++,
        _logger_object_                      => $i++,
        _unexpected_error_count_             => $i++,
        _started_looking_for_here_target_at_ => $i++,
        _nearly_matched_here_target_at_      => $i++,
        _line_of_text_                       => $i++,
        _rlower_case_labels_at_              => $i++,
        _extended_syntax_                    => $i++,
        _maximum_level_                      => $i++,
        _true_brace_error_count_             => $i++,
        _rOpts_maximum_level_errors_         => $i++,
        _rOpts_maximum_unexpected_errors_    => $i++,
        _rOpts_logfile_                      => $i++,
        _rOpts_                              => $i++,
    };
}

{    ## closure for subs to count instances

    # methods to count instances
    my $_count = 0;
    sub get_count        { return $_count; }
    sub _increment_count { return ++$_count }
    sub _decrement_count { return --$_count }
}

sub DESTROY {
    my $self = shift;
    $self->_decrement_count();
    return;
}

sub AUTOLOAD {

    # Catch any undefined sub calls so that we are sure to get
    # some diagnostic information.  This sub should never be called
    # except for a programming error.
    our $AUTOLOAD;
    return if ( $AUTOLOAD =~ /\bDESTROY$/ );
    my ( $pkg, $fname, $lno ) = caller();
    my $my_package = __PACKAGE__;
    print STDERR <<EOM;
======================================================================
Error detected in package '$my_package', version $VERSION
Received unexpected AUTOLOAD call for sub '$AUTOLOAD'
Called from package: '$pkg'  
Called from File '$fname'  at line '$lno'
This error is probably due to a recent programming change
======================================================================
EOM
    exit 1;
}

sub Die {
    my ($msg) = @_;
    Perl::Tidy::Die($msg);
    croak "unexpected return from Perl::Tidy::Die";
}

sub Fault {
    my ($msg) = @_;

    # This routine is called for errors that really should not occur
    # except if there has been a bug introduced by a recent program change.
    # Please add comments at calls to Fault to explain why the call
    # should not occur, and where to look to fix it.
    my ( $package0, $filename0, $line0, $subroutine0 ) = caller(0);
    my ( $package1, $filename1, $line1, $subroutine1 ) = caller(1);
    my ( $package2, $filename2, $line2, $subroutine2 ) = caller(2);
    my $input_stream_name = get_input_stream_name();

    Die(<<EOM);
==============================================================================
While operating on input stream with name: '$input_stream_name'
A fault was detected at line $line0 of sub '$subroutine1'
in file '$filename1'
which was called from line $line1 of sub '$subroutine2'
Message: '$msg'
This is probably an error introduced by a recent programming change.
Perl::Tidy::Tokenizer.pm reports VERSION='$VERSION'.
==============================================================================
EOM

    # We shouldn't get here, but this return is to keep Perl-Critic from
    # complaining.
    return;
}

sub bad_pattern {

    # See if a pattern will compile. We have to use a string eval here,
    # but it should be safe because the pattern has been constructed
    # by this program.
    my ($pattern) = @_;
    eval "'##'=~/$pattern/";
    return $@;
}

sub make_code_skipping_pattern {
    my ( $rOpts, $opt_name, $default ) = @_;
    my $param = $rOpts->{$opt_name};
    unless ($param) { $param = $default }
    $param =~ s/^\s*//;    # allow leading spaces to be like format-skipping
    if ( $param !~ /^#/ ) {
        Die("ERROR: the $opt_name parameter '$param' must begin with '#'\n");
    }
    my $pattern = '^\s*' . $param . '\b';
    if ( bad_pattern($pattern) ) {
        Die(
"ERROR: the $opt_name parameter '$param' causes the invalid regex '$pattern'\n"
        );
    }
    return $pattern;
}

sub check_options {

    # Check Tokenizer parameters
    my $rOpts = shift;

    %is_sub = ();
    $is_sub{'sub'} = 1;

    # Install any aliases to 'sub'
    if ( $rOpts->{'sub-alias-list'} ) {

        # Note that any 'sub-alias-list' has been preprocessed to
        # be a trimmed, space-separated list which includes 'sub'
        # for example, it might be 'sub method fun'
        my @sub_alias_list = split /\s+/, $rOpts->{'sub-alias-list'};
        foreach my $word (@sub_alias_list) {
            $is_sub{$word} = 1;
        }
    }

    %is_grep_alias = ();
    if ( $rOpts->{'grep-alias-list'} ) {

        # Note that 'grep-alias-list' has been preprocessed to be a trimmed,
        # space-separated list
        my @q = split /\s+/, $rOpts->{'grep-alias-list'};
        @{is_grep_alias}{@q} = (1) x scalar(@q);
    }

    $rOpts_code_skipping = $rOpts->{'code-skipping'};
    $code_skipping_pattern_begin =
      make_code_skipping_pattern( $rOpts, 'code-skipping-begin', '#<<V' );
    $code_skipping_pattern_end =
      make_code_skipping_pattern( $rOpts, 'code-skipping-end', '#>>V' );
    return;
}

sub new {

    my ( $class, @args ) = @_;

    # Note: 'tabs' and 'indent_columns' are temporary and should be
    # removed asap
    my %defaults = (
        source_object        => undef,
        debugger_object      => undef,
        diagnostics_object   => undef,
        logger_object        => undef,
        starting_level       => undef,
        indent_columns       => 4,
        tabsize              => 8,
        look_for_hash_bang   => 0,
        trim_qw              => 1,
        look_for_autoloader  => 1,
        look_for_selfloader  => 1,
        starting_line_number => 1,
        extended_syntax      => 0,
        rOpts                => {},
    );
    my %args = ( %defaults, @args );

    # we are given an object with a get_line() method to supply source lines
    my $source_object = $args{source_object};
    my $rOpts         = $args{rOpts};

    # we create another object with a get_line() and peek_ahead() method
    my $line_buffer_object = Perl::Tidy::LineBuffer->new($source_object);

    # Tokenizer state data is as follows:
    # _rhere_target_list_    reference to list of here-doc targets
    # _here_doc_target_      the target string for a here document
    # _here_quote_character_ the type of here-doc quoting (" ' ` or none)
    #                        to determine if interpolation is done
    # _quote_target_         character we seek if chasing a quote
    # _line_start_quote_     line where we started looking for a long quote
    # _in_here_doc_          flag indicating if we are in a here-doc
    # _in_pod_               flag set if we are in pod documentation
    # _in_skipped_           flag set if we are in a skipped section
    # _in_error_             flag set if we saw severe error (binary in script)
    # _in_data_              flag set if we are in __DATA__ section
    # _in_end_               flag set if we are in __END__ section
    # _in_format_            flag set if we are in a format description
    # _in_attribute_list_    flag telling if we are looking for attributes
    # _in_quote_             flag telling if we are chasing a quote
    # _starting_level_       indentation level of first line
    # _line_buffer_object_   object with get_line() method to supply source code
    # _diagnostics_object_   place to write debugging information
    # _unexpected_error_count_ error count used to limit output
    # _lower_case_labels_at_ line numbers where lower case labels seen
    # _hit_bug_              program bug detected

    my $self = [];
    $self->[_rhere_target_list_]        = [];
    $self->[_in_here_doc_]              = 0;
    $self->[_here_doc_target_]          = "";
    $self->[_here_quote_character_]     = "";
    $self->[_in_data_]                  = 0;
    $self->[_in_end_]                   = 0;
    $self->[_in_format_]                = 0;
    $self->[_in_error_]                 = 0;
    $self->[_in_pod_]                   = 0;
    $self->[_in_skipped_]               = 0;
    $self->[_in_attribute_list_]        = 0;
    $self->[_in_quote_]                 = 0;
    $self->[_quote_target_]             = "";
    $self->[_line_start_quote_]         = -1;
    $self->[_starting_level_]           = $args{starting_level};
    $self->[_know_starting_level_]      = defined( $args{starting_level} );
    $self->[_tabsize_]                  = $args{tabsize};
    $self->[_indent_columns_]           = $args{indent_columns};
    $self->[_look_for_hash_bang_]       = $args{look_for_hash_bang};
    $self->[_trim_qw_]                  = $args{trim_qw};
    $self->[_continuation_indentation_] = $args{continuation_indentation};
    $self->[_outdent_labels_]           = $args{outdent_labels};
    $self->[_last_line_number_]         = $args{starting_line_number} - 1;
    $self->[_saw_perl_dash_P_]          = 0;
    $self->[_saw_perl_dash_w_]          = 0;
    $self->[_saw_use_strict_]           = 0;
    $self->[_saw_v_string_]             = 0;
    $self->[_hit_bug_]                  = 0;
    $self->[_look_for_autoloader_]      = $args{look_for_autoloader};
    $self->[_look_for_selfloader_]      = $args{look_for_selfloader};
    $self->[_saw_autoloader_]           = 0;
    $self->[_saw_selfloader_]           = 0;
    $self->[_saw_hash_bang_]            = 0;
    $self->[_saw_end_]                  = 0;
    $self->[_saw_data_]                 = 0;
    $self->[_saw_negative_indentation_] = 0;
    $self->[_started_tokenizing_]       = 0;
    $self->[_line_buffer_object_]       = $line_buffer_object;
    $self->[_debugger_object_]          = $args{debugger_object};
    $self->[_diagnostics_object_]       = $args{diagnostics_object};
    $self->[_logger_object_]            = $args{logger_object};
    $self->[_unexpected_error_count_]   = 0;
    $self->[_started_looking_for_here_target_at_] = 0;
    $self->[_nearly_matched_here_target_at_]      = undef;
    $self->[_line_of_text_]                       = "";
    $self->[_rlower_case_labels_at_]              = undef;
    $self->[_extended_syntax_]                    = $args{extended_syntax};
    $self->[_maximum_level_]                      = 0;
    $self->[_true_brace_error_count_]             = 0;
    $self->[_rOpts_maximum_level_errors_] = $rOpts->{'maximum-level-errors'};
    $self->[_rOpts_maximum_unexpected_errors_] =
      $rOpts->{'maximum-unexpected-errors'};
    $self->[_rOpts_logfile_] = $rOpts->{'logfile'};
    $self->[_rOpts_]         = $rOpts;
    bless $self, $class;

    $tokenizer_self = $self;

    prepare_for_a_new_file();
    find_starting_indentation_level();

    # This is not a full class yet, so die if an attempt is made to
    # create more than one object.

    if ( _increment_count() > 1 ) {
        confess
"Attempt to create more than 1 object in $class, which is not a true class yet\n";
    }

    return $self;

}

# interface to Perl::Tidy::Logger routines
sub warning {
    my $msg           = shift;
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $logger_object->warning($msg);
    }
    return;
}

sub get_input_stream_name {
    my $input_stream_name = "";
    my $logger_object     = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $input_stream_name = $logger_object->get_input_stream_name();
    }
    return $input_stream_name;
}

sub complain {
    my $msg           = shift;
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $logger_object->complain($msg);
    }
    return;
}

sub write_logfile_entry {
    my $msg           = shift;
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $logger_object->write_logfile_entry($msg);
    }
    return;
}

sub interrupt_logfile {
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $logger_object->interrupt_logfile();
    }
    return;
}

sub resume_logfile {
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $logger_object->resume_logfile();
    }
    return;
}

sub increment_brace_error {
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $logger_object->increment_brace_error();
    }
    return;
}

sub report_definite_bug {
    $tokenizer_self->[_hit_bug_] = 1;
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $logger_object->report_definite_bug();
    }
    return;
}

sub brace_warning {
    my $msg           = shift;
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        $logger_object->brace_warning($msg);
    }
    return;
}

sub get_saw_brace_error {
    my $logger_object = $tokenizer_self->[_logger_object_];
    if ($logger_object) {
        return $logger_object->get_saw_brace_error();
    }
    else {
        return 0;
    }
}

sub get_unexpected_error_count {
    my ($self) = @_;
    return $self->[_unexpected_error_count_];
}

# interface to Perl::Tidy::Diagnostics routines
sub write_diagnostics {
    my $msg = shift;
    if ( $tokenizer_self->[_diagnostics_object_] ) {
        $tokenizer_self->[_diagnostics_object_]->write_diagnostics($msg);
    }
    return;
}

sub get_maximum_level {
    return $tokenizer_self->[_maximum_level_];
}

sub report_tokenization_errors {

    my ($self) = @_;

    # Report any tokenization errors and return a flag '$severe_error'.
    # Set $severe_error = 1 if the tokenizations errors are so severe that
    # the formatter should not attempt to format the file. Instead, it will
    # just output the file verbatim.

    # set severe error flag if tokenizer has encountered file reading problems
    # (i.e. unexpected binary characters)
    my $severe_error = $self->[_in_error_];

    my $maxle = $self->[_rOpts_maximum_level_errors_];
    my $maxue = $self->[_rOpts_maximum_unexpected_errors_];
    $maxle = 1 unless defined($maxle);
    $maxue = 0 unless defined($maxue);

    my $level = get_indentation_level();
    if ( $level != $tokenizer_self->[_starting_level_] ) {
        warning("final indentation level: $level\n");
        my $level_diff = $tokenizer_self->[_starting_level_] - $level;
        if ( $level_diff < 0 ) { $level_diff = -$level_diff }

        # Set severe error flag if the level error is greater than 1.
        # The formatter can function for any level error but it is probably
        # best not to attempt formatting for a high level error.
        if ( $maxle >= 0 && $level_diff > $maxle ) {
            $severe_error = 1;
            warning(<<EOM);
Formatting will be skipped because level error '$level_diff' exceeds -maxle=$maxle; use -maxle=-1 to force formatting
EOM
        }
    }

    check_final_nesting_depths();

    # Likewise, large numbers of brace errors usually indicate non-perl
    # scirpts, so set the severe error flag at a low number.  This is similar
    # to the level check, but different because braces may balance but be
    # incorrectly interlaced.
    if ( $tokenizer_self->[_true_brace_error_count_] > 2 ) {
        $severe_error = 1;
    }

    if ( $tokenizer_self->[_look_for_hash_bang_]
        && !$tokenizer_self->[_saw_hash_bang_] )
    {
        warning(
            "hit EOF without seeing hash-bang line; maybe don't need -x?\n");
    }

    if ( $tokenizer_self->[_in_format_] ) {
        warning("hit EOF while in format description\n");
    }

    if ( $tokenizer_self->[_in_skipped_] ) {
        write_logfile_entry(
            "hit EOF while in lines skipped with --code-skipping\n");
    }

    if ( $tokenizer_self->[_in_pod_] ) {

        # Just write log entry if this is after __END__ or __DATA__
        # because this happens to often, and it is not likely to be
        # a parsing error.
        if ( $tokenizer_self->[_saw_data_] || $tokenizer_self->[_saw_end_] ) {
            write_logfile_entry(
"hit eof while in pod documentation (no =cut seen)\n\tthis can cause trouble with some pod utilities\n"
            );
        }

        else {
            complain(
"hit eof while in pod documentation (no =cut seen)\n\tthis can cause trouble with some pod utilities\n"
            );
        }

    }

    if ( $tokenizer_self->[_in_here_doc_] ) {
        $severe_error = 1;
        my $here_doc_target = $tokenizer_self->[_here_doc_target_];
        my $started_looking_for_here_target_at =
          $tokenizer_self->[_started_looking_for_here_target_at_];
        if ($here_doc_target) {
            warning(
"hit EOF in here document starting at line $started_looking_for_here_target_at with target: $here_doc_target\n"
            );
        }
        else {
            warning(<<EOM);
Hit EOF in here document starting at line $started_looking_for_here_target_at with empty target string.
  (Perl will match to the end of file but this may not be intended).
EOM
        }
        my $nearly_matched_here_target_at =
          $tokenizer_self->[_nearly_matched_here_target_at_];
        if ($nearly_matched_here_target_at) {
            warning(
"NOTE: almost matched at input line $nearly_matched_here_target_at except for whitespace\n"
            );
        }
    }

    # Something is seriously wrong if we ended inside a quote
    if ( $tokenizer_self->[_in_quote_] ) {
        $severe_error = 1;
        my $line_start_quote = $tokenizer_self->[_line_start_quote_];
        my $quote_target     = $tokenizer_self->[_quote_target_];
        my $what =
          ( $tokenizer_self->[_in_attribute_list_] )
          ? "attribute list"
          : "quote/pattern";
        warning(
"hit EOF seeking end of $what starting at line $line_start_quote ending in $quote_target\n"
        );
    }

    if ( $tokenizer_self->[_hit_bug_] ) {
        $severe_error = 1;
    }

    # Multiple "unexpected" type tokenization errors usually indicate parsing
    # non-perl scripts, or that something is seriously wrong, so we should
    # avoid formatting them.  This can happen for example if we run perltidy on
    # a shell script or an html file.  But unfortunately this check can
    # interfere with some extended syntaxes, such as RPerl, so it has to be off
    # by default.
    my $ue_count = $tokenizer_self->[_unexpected_error_count_];
    if ( $maxue > 0 && $ue_count > $maxue ) {
        warning(<<EOM);
Formatting will be skipped since unexpected token count = $ue_count > -maxue=$maxue; use -maxue=0 to force formatting
EOM
        $severe_error = 1;
    }

    unless ( $tokenizer_self->[_saw_perl_dash_w_] ) {
        if ( $] < 5.006 ) {
            write_logfile_entry("Suggest including '-w parameter'\n");
        }
        else {
            write_logfile_entry("Suggest including 'use warnings;'\n");
        }
    }

    if ( $tokenizer_self->[_saw_perl_dash_P_] ) {
        write_logfile_entry("Use of -P parameter for defines is discouraged\n");
    }

    unless ( $tokenizer_self->[_saw_use_strict_] ) {
        write_logfile_entry("Suggest including 'use strict;'\n");
    }

    # it is suggested that labels have at least one upper case character
    # for legibility and to avoid code breakage as new keywords are introduced
    if ( $tokenizer_self->[_rlower_case_labels_at_] ) {
        my @lower_case_labels_at =
          @{ $tokenizer_self->[_rlower_case_labels_at_] };
        write_logfile_entry(
            "Suggest using upper case characters in label(s)\n");
        local $" = ')(';
        write_logfile_entry("  defined at line(s): (@lower_case_labels_at)\n");
    }
    return $severe_error;
}

sub report_v_string {

    # warn if this version can't handle v-strings
    my $tok = shift;
    unless ( $tokenizer_self->[_saw_v_string_] ) {
        $tokenizer_self->[_saw_v_string_] =
          $tokenizer_self->[_last_line_number_];
    }
    if ( $] < 5.006 ) {
        warning(
"Found v-string '$tok' but v-strings are not implemented in your version of perl; see Camel 3 book ch 2\n"
        );
    }
    return;
}

sub is_valid_token_type {
    my ($type) = @_;
    return $is_valid_token_type{$type};
}

sub get_input_line_number {
    return $tokenizer_self->[_last_line_number_];
}

# returns the next tokenized line
sub get_line {

    my $self = shift;

    # USES GLOBAL VARIABLES: $tokenizer_self, $brace_depth,
    # $square_bracket_depth, $paren_depth

    my $input_line = $tokenizer_self->[_line_buffer_object_]->get_line();
    $tokenizer_self->[_line_of_text_] = $input_line;

    return unless ($input_line);

    my $input_line_number = ++$tokenizer_self->[_last_line_number_];

    my $write_logfile_entry = sub {
        my ($msg) = @_;
        write_logfile_entry("Line $input_line_number: $msg");
        return;
    };

    # Find and remove what characters terminate this line, including any
    # control r
    my $input_line_separator = "";
    if ( chomp($input_line) ) { $input_line_separator = $/ }

    # The first test here very significantly speeds things up, but be sure to
    # keep the regex and hash %other_line_endings the same.
    if ( $other_line_endings{ substr( $input_line, -1 ) } ) {
        if ( $input_line =~ s/((\r|\035|\032)+)$// ) {
            $input_line_separator = $2 . $input_line_separator;
        }
    }

    # for backwards compatibility we keep the line text terminated with
    # a newline character
    $input_line .= "\n";
    $tokenizer_self->[_line_of_text_] = $input_line;    # update

    # create a data structure describing this line which will be
    # returned to the caller.

    # _line_type codes are:
    #   SYSTEM         - system-specific code before hash-bang line
    #   CODE           - line of perl code (including comments)
    #   POD_START      - line starting pod, such as '=head'
    #   POD            - pod documentation text
    #   POD_END        - last line of pod section, '=cut'
    #   HERE           - text of here-document
    #   HERE_END       - last line of here-doc (target word)
    #   FORMAT         - format section
    #   FORMAT_END     - last line of format section, '.'
    #   SKIP           - code skipping section
    #   SKIP_END       - last line of code skipping section, '#>>V'
    #   DATA_START     - __DATA__ line
    #   DATA           - unidentified text following __DATA__
    #   END_START      - __END__ line
    #   END            - unidentified text following __END__
    #   ERROR          - we are in big trouble, probably not a perl script

    # Other variables:
    #   _curly_brace_depth     - depth of curly braces at start of line
    #   _square_bracket_depth  - depth of square brackets at start of line
    #   _paren_depth           - depth of parens at start of line
    #   _starting_in_quote     - this line continues a multi-line quote
    #                            (so don't trim leading blanks!)
    #   _ending_in_quote       - this line ends in a multi-line quote
    #                            (so don't trim trailing blanks!)
    my $line_of_tokens = {
        _line_type                 => 'EOF',
        _line_text                 => $input_line,
        _line_number               => $input_line_number,
        _guessed_indentation_level => 0,
        _curly_brace_depth         => $brace_depth,
        _square_bracket_depth      => $square_bracket_depth,
        _paren_depth               => $paren_depth,
        _quote_character           => '',
##        _rtoken_type               => undef,
##        _rtokens                   => undef,
##        _rlevels                   => undef,
##        _rslevels                  => undef,
##        _rblock_type               => undef,
##        _rcontainer_type           => undef,
##        _rcontainer_environment    => undef,
##        _rtype_sequence            => undef,
##        _rnesting_tokens           => undef,
##        _rci_levels                => undef,
##        _rnesting_blocks           => undef,
##        _starting_in_quote         => 0,
##        _ending_in_quote           => 0,
    };

    # must print line unchanged if we are in a here document
    if ( $tokenizer_self->[_in_here_doc_] ) {

        $line_of_tokens->{_line_type} = 'HERE';
        my $here_doc_target      = $tokenizer_self->[_here_doc_target_];
        my $here_quote_character = $tokenizer_self->[_here_quote_character_];
        my $candidate_target     = $input_line;
        chomp $candidate_target;

        # Handle <<~ targets, which are indicated here by a leading space on
        # the here quote character
        if ( $here_quote_character =~ /^\s/ ) {
            $candidate_target =~ s/^\s*//;
        }
        if ( $candidate_target eq $here_doc_target ) {
            $tokenizer_self->[_nearly_matched_here_target_at_] = undef;
            $line_of_tokens->{_line_type} = 'HERE_END';
            $write_logfile_entry->("Exiting HERE document $here_doc_target\n");

            my $rhere_target_list = $tokenizer_self->[_rhere_target_list_];
            if ( @{$rhere_target_list} ) {  # there can be multiple here targets
                ( $here_doc_target, $here_quote_character ) =
                  @{ shift @{$rhere_target_list} };
                $tokenizer_self->[_here_doc_target_] = $here_doc_target;
                $tokenizer_self->[_here_quote_character_] =
                  $here_quote_character;
                $write_logfile_entry->(
                    "Entering HERE document $here_doc_target\n");
                $tokenizer_self->[_nearly_matched_here_target_at_] = undef;
                $tokenizer_self->[_started_looking_for_here_target_at_] =
                  $input_line_number;
            }
            else {
                $tokenizer_self->[_in_here_doc_]          = 0;
                $tokenizer_self->[_here_doc_target_]      = "";
                $tokenizer_self->[_here_quote_character_] = "";
            }
        }

        # check for error of extra whitespace
        # note for PERL6: leading whitespace is allowed
        else {
            $candidate_target =~ s/\s*$//;
            $candidate_target =~ s/^\s*//;
            if ( $candidate_target eq $here_doc_target ) {
                $tokenizer_self->[_nearly_matched_here_target_at_] =
                  $input_line_number;
            }
        }
        return $line_of_tokens;
    }

    # Print line unchanged if we are in a format section
    elsif ( $tokenizer_self->[_in_format_] ) {

        if ( $input_line =~ /^\.[\s#]*$/ ) {

            # Decrement format depth count at a '.' after a 'format'
            $tokenizer_self->[_in_format_]--;

            # This is the end when count reaches 0
            if ( !$tokenizer_self->[_in_format_] ) {
                $write_logfile_entry->("Exiting format section\n");
                $line_of_tokens->{_line_type} = 'FORMAT_END';
            }
        }
        else {
            $line_of_tokens->{_line_type} = 'FORMAT';
            if ( $input_line =~ /^\s*format\s+\w+/ ) {

                # Increment format depth count at a 'format' within a 'format'
                # This is a simple way to handle nested formats (issue c019).
                $tokenizer_self->[_in_format_]++;
            }
        }
        return $line_of_tokens;
    }

    # must print line unchanged if we are in pod documentation
    elsif ( $tokenizer_self->[_in_pod_] ) {

        $line_of_tokens->{_line_type} = 'POD';
        if ( $input_line =~ /^=cut/ ) {
            $line_of_tokens->{_line_type} = 'POD_END';
            $write_logfile_entry->("Exiting POD section\n");
            $tokenizer_self->[_in_pod_] = 0;
        }
        if ( $input_line =~ /^\#\!.*perl\b/ && !$tokenizer_self->[_in_end_] ) {
            warning(
                "Hash-bang in pod can cause older versions of perl to fail! \n"
            );
        }

        return $line_of_tokens;
    }

    # print line unchanged if in skipped section
    elsif ( $tokenizer_self->[_in_skipped_] ) {

        $line_of_tokens->{_line_type} = 'SKIP';
        if ( $input_line =~ /$code_skipping_pattern_end/ ) {
            $line_of_tokens->{_line_type} = 'SKIP_END';
            $write_logfile_entry->("Exiting code-skipping section\n");
            $tokenizer_self->[_in_skipped_] = 0;
        }
        return $line_of_tokens;
    }

    # must print line unchanged if we have seen a severe error (i.e., we
    # are seeing illegal tokens and cannot continue.  Syntax errors do
    # not pass this route).  Calling routine can decide what to do, but
    # the default can be to just pass all lines as if they were after __END__
    elsif ( $tokenizer_self->[_in_error_] ) {
        $line_of_tokens->{_line_type} = 'ERROR';
        return $line_of_tokens;
    }

    # print line unchanged if we are __DATA__ section
    elsif ( $tokenizer_self->[_in_data_] ) {

        # ...but look for POD
        # Note that the _in_data and _in_end flags remain set
        # so that we return to that state after seeing the
        # end of a pod section
        if ( $input_line =~ /^=(\w+)\b/ && $1 ne 'cut' ) {
            $line_of_tokens->{_line_type} = 'POD_START';
            $write_logfile_entry->("Entering POD section\n");
            $tokenizer_self->[_in_pod_] = 1;
            return $line_of_tokens;
        }
        else {
            $line_of_tokens->{_line_type} = 'DATA';
            return $line_of_tokens;
        }
    }

    # print line unchanged if we are in __END__ section
    elsif ( $tokenizer_self->[_in_end_] ) {

        # ...but look for POD
        # Note that the _in_data and _in_end flags remain set
        # so that we return to that state after seeing the
        # end of a pod section
        if ( $input_line =~ /^=(\w+)\b/ && $1 ne 'cut' ) {
            $line_of_tokens->{_line_type} = 'POD_START';
            $write_logfile_entry->("Entering POD section\n");
            $tokenizer_self->[_in_pod_] = 1;
            return $line_of_tokens;
        }
        else {
            $line_of_tokens->{_line_type} = 'END';
            return $line_of_tokens;
        }
    }

    # check for a hash-bang line if we haven't seen one
    if ( !$tokenizer_self->[_saw_hash_bang_] ) {
        if ( $input_line =~ /^\#\!.*perl\b/ ) {
            $tokenizer_self->[_saw_hash_bang_] = $input_line_number;

            # check for -w and -P flags
            if ( $input_line =~ /^\#\!.*perl\s.*-.*P/ ) {
                $tokenizer_self->[_saw_perl_dash_P_] = 1;
            }

            if ( $input_line =~ /^\#\!.*perl\s.*-.*w/ ) {
                $tokenizer_self->[_saw_perl_dash_w_] = 1;
            }

            if (
                $input_line_number > 1

                # leave any hash bang in a BEGIN block alone
                # i.e. see 'debugger-duck_type.t'
                && !(
                       $last_nonblank_block_type
                    && $last_nonblank_block_type eq 'BEGIN'
                )
                && !$tokenizer_self->[_look_for_hash_bang_]

                # Try to avoid giving a false alarm at a simple comment.
                # These look like valid hash-bang lines:

                #!/usr/bin/perl -w
                #!   /usr/bin/perl -w
                #!c:\perl\bin\perl.exe

                # These are comments:
                #! I love perl
                #!  sunos does not yet provide a /usr/bin/perl

                # Comments typically have multiple spaces, which suggests
                # the filter
                && $input_line =~ /^\#\!(\s+)?(\S+)?perl/
              )
            {

                # this is helpful for VMS systems; we may have accidentally
                # tokenized some DCL commands
                if ( $tokenizer_self->[_started_tokenizing_] ) {
                    warning(
"There seems to be a hash-bang after line 1; do you need to run with -x ?\n"
                    );
                }
                else {
                    complain("Useless hash-bang after line 1\n");
                }
            }

            # Report the leading hash-bang as a system line
            # This will prevent -dac from deleting it
            else {
                $line_of_tokens->{_line_type} = 'SYSTEM';
                return $line_of_tokens;
            }
        }
    }

    # wait for a hash-bang before parsing if the user invoked us with -x
    if ( $tokenizer_self->[_look_for_hash_bang_]
        && !$tokenizer_self->[_saw_hash_bang_] )
    {
        $line_of_tokens->{_line_type} = 'SYSTEM';
        return $line_of_tokens;
    }

    # a first line of the form ': #' will be marked as SYSTEM
    # since lines of this form may be used by tcsh
    if ( $input_line_number == 1 && $input_line =~ /^\s*\:\s*\#/ ) {
        $line_of_tokens->{_line_type} = 'SYSTEM';
        return $line_of_tokens;
    }

    # now we know that it is ok to tokenize the line...
    # the line tokenizer will modify any of these private variables:
    #        _rhere_target_list_
    #        _in_data_
    #        _in_end_
    #        _in_format_
    #        _in_error_
    #        _in_skipped_
    #        _in_pod_
    #        _in_quote_
    my $ending_in_quote_last = $tokenizer_self->[_in_quote_];
    tokenize_this_line($line_of_tokens);

    # Now finish defining the return structure and return it
    $line_of_tokens->{_ending_in_quote} = $tokenizer_self->[_in_quote_];

    # handle severe error (binary data in script)
    if ( $tokenizer_self->[_in_error_] ) {
        $tokenizer_self->[_in_quote_] = 0;    # to avoid any more messages
        warning("Giving up after error\n");
        $line_of_tokens->{_line_type} = 'ERROR';
        reset_indentation_level(0);           # avoid error messages
        return $line_of_tokens;
    }

    # handle start of pod documentation
    if ( $tokenizer_self->[_in_pod_] ) {

        # This gets tricky..above a __DATA__ or __END__ section, perl
        # accepts '=cut' as the start of pod section. But afterwards,
        # only pod utilities see it and they may ignore an =cut without
        # leading =head.  In any case, this isn't good.
        if ( $input_line =~ /^=cut\b/ ) {
            if ( $tokenizer_self->[_saw_data_] || $tokenizer_self->[_saw_end_] )
            {
                complain("=cut while not in pod ignored\n");
                $tokenizer_self->[_in_pod_] = 0;
                $line_of_tokens->{_line_type} = 'POD_END';
            }
            else {
                $line_of_tokens->{_line_type} = 'POD_START';
                warning(
"=cut starts a pod section .. this can fool pod utilities.\n"
                ) unless (DEVEL_MODE);
                $write_logfile_entry->("Entering POD section\n");
            }
        }

        else {
            $line_of_tokens->{_line_type} = 'POD_START';
            $write_logfile_entry->("Entering POD section\n");
        }

        return $line_of_tokens;
    }

    # handle start of skipped section
    if ( $tokenizer_self->[_in_skipped_] ) {

        $line_of_tokens->{_line_type} = 'SKIP';
        $write_logfile_entry->("Entering code-skipping section\n");
        return $line_of_tokens;
    }

    # Update indentation levels for log messages.
    # Skip blank lines and also block comments, unless a logfile is requested.
    # Note that _line_of_text_ is the input line but trimmed from left to right.
    my $lot = $tokenizer_self->[_line_of_text_];
    if ( $lot && ( $self->[_rOpts_logfile_] || substr( $lot, 0, 1 ) ne '#' ) ) {
        my $rlevels = $line_of_tokens->{_rlevels};
        $line_of_tokens->{_guessed_indentation_level} =
          guess_old_indentation_level($input_line);
    }

    # see if this line contains here doc targets
    my $rhere_target_list = $tokenizer_self->[_rhere_target_list_];
    if ( @{$rhere_target_list} ) {

        my ( $here_doc_target, $here_quote_character ) =
          @{ shift @{$rhere_target_list} };
        $tokenizer_self->[_in_here_doc_]          = 1;
        $tokenizer_self->[_here_doc_target_]      = $here_doc_target;
        $tokenizer_self->[_here_quote_character_] = $here_quote_character;
        $write_logfile_entry->("Entering HERE document $here_doc_target\n");
        $tokenizer_self->[_started_looking_for_here_target_at_] =
          $input_line_number;
    }

    # NOTE: __END__ and __DATA__ statements are written unformatted
    # because they can theoretically contain additional characters
    # which are not tokenized (and cannot be read with <DATA> either!).
    if ( $tokenizer_self->[_in_data_] ) {
        $line_of_tokens->{_line_type} = 'DATA_START';
        $write_logfile_entry->("Starting __DATA__ section\n");
        $tokenizer_self->[_saw_data_] = 1;

        # keep parsing after __DATA__ if use SelfLoader was seen
        if ( $tokenizer_self->[_saw_selfloader_] ) {
            $tokenizer_self->[_in_data_] = 0;
            $write_logfile_entry->(
                "SelfLoader seen, continuing; -nlsl deactivates\n");
        }

        return $line_of_tokens;
    }

    elsif ( $tokenizer_self->[_in_end_] ) {
        $line_of_tokens->{_line_type} = 'END_START';
        $write_logfile_entry->("Starting __END__ section\n");
        $tokenizer_self->[_saw_end_] = 1;

        # keep parsing after __END__ if use AutoLoader was seen
        if ( $tokenizer_self->[_saw_autoloader_] ) {
            $tokenizer_self->[_in_end_] = 0;
            $write_logfile_entry->(
                "AutoLoader seen, continuing; -nlal deactivates\n");
        }
        return $line_of_tokens;
    }

    # now, finally, we know that this line is type 'CODE'
    $line_of_tokens->{_line_type} = 'CODE';

    # remember if we have seen any real code
    if (  !$tokenizer_self->[_started_tokenizing_]
        && $input_line !~ /^\s*$/
        && $input_line !~ /^\s*#/ )
    {
        $tokenizer_self->[_started_tokenizing_] = 1;
    }

    if ( $tokenizer_self->[_debugger_object_] ) {
        $tokenizer_self->[_debugger_object_]
          ->write_debug_entry($line_of_tokens);
    }

    # Note: if keyword 'format' occurs in this line code, it is still CODE
    # (keyword 'format' need not start a line)
    if ( $tokenizer_self->[_in_format_] ) {
        $write_logfile_entry->("Entering format section\n");
    }

    if ( $tokenizer_self->[_in_quote_]
        and ( $tokenizer_self->[_line_start_quote_] < 0 ) )
    {

        #if ( ( my $quote_target = get_quote_target() ) !~ /^\s*$/ ) {
        if ( ( my $quote_target = $tokenizer_self->[_quote_target_] ) !~
            /^\s*$/ )
        {
            $tokenizer_self->[_line_start_quote_] = $input_line_number;
            $write_logfile_entry->(
                "Start multi-line quote or pattern ending in $quote_target\n");
        }
    }
    elsif ( ( $tokenizer_self->[_line_start_quote_] >= 0 )
        && !$tokenizer_self->[_in_quote_] )
    {
        $tokenizer_self->[_line_start_quote_] = -1;
        $write_logfile_entry->("End of multi-line quote or pattern\n");
    }

    # we are returning a line of CODE
    return $line_of_tokens;
}

sub find_starting_indentation_level {

    # We need to find the indentation level of the first line of the
    # script being formatted.  Often it will be zero for an entire file,
    # but if we are formatting a local block of code (within an editor for
    # example) it may not be zero.  The user may specify this with the
    # -sil=n parameter but normally doesn't so we have to guess.
    #
    # USES GLOBAL VARIABLES: $tokenizer_self
    my $starting_level = 0;

    # use value if given as parameter
    if ( $tokenizer_self->[_know_starting_level_] ) {
        $starting_level = $tokenizer_self->[_starting_level_];
    }

    # if we know there is a hash_bang line, the level must be zero
    elsif ( $tokenizer_self->[_look_for_hash_bang_] ) {
        $tokenizer_self->[_know_starting_level_] = 1;
    }

    # otherwise figure it out from the input file
    else {
        my $line;
        my $i = 0;

        # keep looking at lines until we find a hash bang or piece of code
        my $msg = "";
        while ( $line =
            $tokenizer_self->[_line_buffer_object_]->peek_ahead( $i++ ) )
        {

            # if first line is #! then assume starting level is zero
            if ( $i == 1 && $line =~ /^\#\!/ ) {
                $starting_level = 0;
                last;
            }
            next if ( $line =~ /^\s*#/ );    # skip past comments
            next if ( $line =~ /^\s*$/ );    # skip past blank lines
            $starting_level = guess_old_indentation_level($line);
            last;
        }
        $msg = "Line $i implies starting-indentation-level = $starting_level\n";
        write_logfile_entry("$msg");
    }
    $tokenizer_self->[_starting_level_] = $starting_level;
    reset_indentation_level($starting_level);
    return;
}

sub guess_old_indentation_level {
    my ($line) = @_;

    # Guess the indentation level of an input line.
    #
    # For the first line of code this result will define the starting
    # indentation level.  It will mainly be non-zero when perltidy is applied
    # within an editor to a local block of code.
    #
    # This is an impossible task in general because we can't know what tabs
    # meant for the old script and how many spaces were used for one
    # indentation level in the given input script.  For example it may have
    # been previously formatted with -i=7 -et=3.  But we can at least try to
    # make sure that perltidy guesses correctly if it is applied repeatedly to
    # a block of code within an editor, so that the block stays at the same
    # level when perltidy is applied repeatedly.
    #
    # USES GLOBAL VARIABLES: $tokenizer_self
    my $level = 0;

    # find leading tabs, spaces, and any statement label
    my $spaces = 0;
    if ( $line =~ /^(\t+)?(\s+)?(\w+:[^:])?/ ) {

        # If there are leading tabs, we use the tab scheme for this run, if
        # any, so that the code will remain stable when editing.
        if ($1) { $spaces += length($1) * $tokenizer_self->[_tabsize_] }

        if ($2) { $spaces += length($2) }

        # correct for outdented labels
        if ( $3 && $tokenizer_self->[_outdent_labels_] ) {
            $spaces += $tokenizer_self->[_continuation_indentation_];
        }
    }

    # compute indentation using the value of -i for this run.
    # If -i=0 is used for this run (which is possible) it doesn't matter
    # what we do here but we'll guess that the old run used 4 spaces per level.
    my $indent_columns = $tokenizer_self->[_indent_columns_];
    $indent_columns = 4 if ( !$indent_columns );
    $level          = int( $spaces / $indent_columns );
    return ($level);
}

# This is a currently unused debug routine
sub dump_functions {

    my $fh = *STDOUT;
    foreach my $pkg ( keys %is_user_function ) {
        $fh->print("\nnon-constant subs in package $pkg\n");

        foreach my $sub ( keys %{ $is_user_function{$pkg} } ) {
            my $msg = "";
            if ( $is_block_list_function{$pkg}{$sub} ) {
                $msg = 'block_list';
            }

            if ( $is_block_function{$pkg}{$sub} ) {
                $msg = 'block';
            }
            $fh->print("$sub $msg\n");
        }
    }

    foreach my $pkg ( keys %is_constant ) {
        $fh->print("\nconstants and constant subs in package $pkg\n");

        foreach my $sub ( keys %{ $is_constant{$pkg} } ) {
            $fh->print("$sub\n");
        }
    }
    return;
}

sub prepare_for_a_new_file {

    # previous tokens needed to determine what to expect next
    $last_nonblank_token      = ';';    # the only possible starting state which
    $last_nonblank_type       = ';';    # will make a leading brace a code block
    $last_nonblank_block_type = '';

    # scalars for remembering statement types across multiple lines
    $statement_type    = '';            # '' or 'use' or 'sub..' or 'case..'
    $in_attribute_list = 0;

    # scalars for remembering where we are in the file
    $current_package = "main";
    $context         = UNKNOWN_CONTEXT;

    # hashes used to remember function information
    %is_constant             = ();      # user-defined constants
    %is_user_function        = ();      # user-defined functions
    %user_function_prototype = ();      # their prototypes
    %is_block_function       = ();
    %is_block_list_function  = ();
    %saw_function_definition = ();
    %saw_use_module          = ();

    # variables used to track depths of various containers
    # and report nesting errors
    $paren_depth             = 0;
    $brace_depth             = 0;
    $square_bracket_depth    = 0;
    @current_depth           = (0) x scalar @closing_brace_names;
    $total_depth             = 0;
    @total_depth             = ();
    @nesting_sequence_number = ( 0 .. @closing_brace_names - 1 );
    @current_sequence_number = ();
    $next_sequence_number    = 2;    # The value 1 is reserved for SEQ_ROOT

    @paren_type                     = ();
    @paren_semicolon_count          = ();
    @paren_structural_type          = ();
    @brace_type                     = ();
    @brace_structural_type          = ();
    @brace_context                  = ();
    @brace_package                  = ();
    @square_bracket_type            = ();
    @square_bracket_structural_type = ();
    @depth_array                    = ();
    @nested_ternary_flag            = ();
    @nested_statement_type          = ();
    @starting_line_of_current_depth = ();

    $paren_type[$paren_depth]            = '';
    $paren_semicolon_count[$paren_depth] = 0;
    $paren_structural_type[$brace_depth] = '';
    $brace_type[$brace_depth] = ';';    # identify opening brace as code block
    $brace_structural_type[$brace_depth]                   = '';
    $brace_context[$brace_depth]                           = UNKNOWN_CONTEXT;
    $brace_package[$paren_depth]                           = $current_package;
    $square_bracket_type[$square_bracket_depth]            = '';
    $square_bracket_structural_type[$square_bracket_depth] = '';

    initialize_tokenizer_state();
    return;
}

{    ## closure for sub tokenize_this_line

    use constant BRACE          => 0;
    use constant SQUARE_BRACKET => 1;
    use constant PAREN          => 2;
    use constant QUESTION_COLON => 3;

    # TV1: scalars for processing one LINE.
    # Re-initialized on each entry to sub tokenize_this_line.
    my (
        $block_type,        $container_type,    $expecting,
        $i,                 $i_tok,             $input_line,
        $input_line_number, $last_nonblank_i,   $max_token_index,
        $next_tok,          $next_type,         $peeked_ahead,
        $prototype,         $rhere_target_list, $rtoken_map,
        $rtoken_type,       $rtokens,           $tok,
        $type,              $type_sequence,     $indent_flag,
    );

    # TV2: refs to ARRAYS for processing one LINE
    # Re-initialized on each call.
    my $routput_token_list     = [];    # stack of output token indexes
    my $routput_token_type     = [];    # token types
    my $routput_block_type     = [];    # types of code block
    my $routput_container_type = [];    # paren types, such as if, elsif, ..
    my $routput_type_sequence  = [];    # nesting sequential number
    my $routput_indent_flag    = [];    #

    # TV3: SCALARS for quote variables.  These are initialized with a
    # subroutine call and continually updated as lines are processed.
    my ( $in_quote, $quote_type, $quote_character, $quote_pos, $quote_depth,
        $quoted_string_1, $quoted_string_2, $allowed_quote_modifiers, );

    # TV4: SCALARS for multi-line identifiers and
    # statements. These are initialized with a subroutine call
    # and continually updated as lines are processed.
    my ( $id_scan_state, $identifier, $want_paren, $indented_if_level );

    # TV5: SCALARS for tracking indentation level.
    # Initialized once and continually updated as lines are
    # processed.
    my (
        $nesting_token_string,      $nesting_type_string,
        $nesting_block_string,      $nesting_block_flag,
        $nesting_list_string,       $nesting_list_flag,
        $ci_string_in_tokenizer,    $continuation_string_in_tokenizer,
        $in_statement_continuation, $level_in_tokenizer,
        $slevel_in_tokenizer,       $rslevel_stack,
    );

    # TV6: SCALARS for remembering several previous
    # tokens. Initialized once and continually updated as
    # lines are processed.
    my (
        $last_nonblank_container_type,     $last_nonblank_type_sequence,
        $last_last_nonblank_token,         $last_last_nonblank_type,
        $last_last_nonblank_block_type,    $last_last_nonblank_container_type,
        $last_last_nonblank_type_sequence, $last_nonblank_prototype,
    );

    # ----------------------------------------------------------------
    # beginning of tokenizer variable access and manipulation routines
    # ----------------------------------------------------------------

    sub initialize_tokenizer_state {

        # TV1: initialized on each call
        # TV2: initialized on each call
        # TV3:
        $in_quote                = 0;
        $quote_type              = 'Q';
        $quote_character         = "";
        $quote_pos               = 0;
        $quote_depth             = 0;
        $quoted_string_1         = "";
        $quoted_string_2         = "";
        $allowed_quote_modifiers = "";

        # TV4:
        $id_scan_state     = '';
        $identifier        = '';
        $want_paren        = "";
        $indented_if_level = 0;

        # TV5:
        $nesting_token_string             = "";
        $nesting_type_string              = "";
        $nesting_block_string             = '1';    # initially in a block
        $nesting_block_flag               = 1;
        $nesting_list_string              = '0';    # initially not in a list
        $nesting_list_flag                = 0;      # initially not in a list
        $ci_string_in_tokenizer           = "";
        $continuation_string_in_tokenizer = "0";
        $in_statement_continuation        = 0;
        $level_in_tokenizer               = 0;
        $slevel_in_tokenizer              = 0;
        $rslevel_stack                    = [];

        # TV6:
        $last_nonblank_container_type      = '';
        $last_nonblank_type_sequence       = '';
        $last_last_nonblank_token          = ';';
        $last_last_nonblank_type           = ';';
        $last_last_nonblank_block_type     = '';
        $last_last_nonblank_container_type = '';
        $last_last_nonblank_type_sequence  = '';
        $last_nonblank_prototype           = "";
        return;
    }

    sub save_tokenizer_state {

        my $rTV1 = [
            $block_type,        $container_type,    $expecting,
            $i,                 $i_tok,             $input_line,
            $input_line_number, $last_nonblank_i,   $max_token_index,
            $next_tok,          $next_type,         $peeked_ahead,
            $prototype,         $rhere_target_list, $rtoken_map,
            $rtoken_type,       $rtokens,           $tok,
            $type,              $type_sequence,     $indent_flag,
        ];

        my $rTV2 = [
            $routput_token_list,    $routput_token_type,
            $routput_block_type,    $routput_container_type,
            $routput_type_sequence, $routput_indent_flag,
        ];

        my $rTV3 = [
            $in_quote,        $quote_type,
            $quote_character, $quote_pos,
            $quote_depth,     $quoted_string_1,
            $quoted_string_2, $allowed_quote_modifiers,
        ];

        my $rTV4 =
          [ $id_scan_state, $identifier, $want_paren, $indented_if_level ];

        my $rTV5 = [
            $nesting_token_string,      $nesting_type_string,
            $nesting_block_string,      $nesting_block_flag,
            $nesting_list_string,       $nesting_list_flag,
            $ci_string_in_tokenizer,    $continuation_string_in_tokenizer,
            $in_statement_continuation, $level_in_tokenizer,
            $slevel_in_tokenizer,       $rslevel_stack,
        ];

        my $rTV6 = [
            $last_nonblank_container_type,
            $last_nonblank_type_sequence,
            $last_last_nonblank_token,
            $last_last_nonblank_type,
            $last_last_nonblank_block_type,
            $last_last_nonblank_container_type,
            $last_last_nonblank_type_sequence,
            $last_nonblank_prototype,
        ];
        return [ $rTV1, $rTV2, $rTV3, $rTV4, $rTV5, $rTV6 ];
    }

    sub restore_tokenizer_state {
        my ($rstate) = @_;
        my ( $rTV1, $rTV2, $rTV3, $rTV4, $rTV5, $rTV6 ) = @{$rstate};
        (
            $block_type,        $container_type,    $expecting,
            $i,                 $i_tok,             $input_line,
            $input_line_number, $last_nonblank_i,   $max_token_index,
            $next_tok,          $next_type,         $peeked_ahead,
            $prototype,         $rhere_target_list, $rtoken_map,
            $rtoken_type,       $rtokens,           $tok,
            $type,              $type_sequence,     $indent_flag,
        ) = @{$rTV1};

        (
            $routput_token_list,    $routput_token_type,
            $routput_block_type,    $routput_container_type,
            $routput_type_sequence, $routput_indent_flag,
        ) = @{$rTV2};

        (
            $in_quote, $quote_type, $quote_character, $quote_pos, $quote_depth,
            $quoted_string_1, $quoted_string_2, $allowed_quote_modifiers,
        ) = @{$rTV3};

        ( $id_scan_state, $identifier, $want_paren, $indented_if_level ) =
          @{$rTV4};

        (
            $nesting_token_string,      $nesting_type_string,
            $nesting_block_string,      $nesting_block_flag,
            $nesting_list_string,       $nesting_list_flag,
            $ci_string_in_tokenizer,    $continuation_string_in_tokenizer,
            $in_statement_continuation, $level_in_tokenizer,
            $slevel_in_tokenizer,       $rslevel_stack,
        ) = @{$rTV5};

        (
            $last_nonblank_container_type,
            $last_nonblank_type_sequence,
            $last_last_nonblank_token,
            $last_last_nonblank_type,
            $last_last_nonblank_block_type,
            $last_last_nonblank_container_type,
            $last_last_nonblank_type_sequence,
            $last_nonblank_prototype,
        ) = @{$rTV6};
        return;
    }

    sub split_pretoken {

        my ($numc) = @_;

     # Split the leading $numc characters from the current token (at index=$i)
     # which is pre-type 'w' and insert the remainder back into the pretoken
     # stream with appropriate settings.  Since we are splitting a pre-type 'w',
     # there are three cases, depending on if the remainder starts with a digit:
     # Case 1: remainder is type 'd', all digits
     # Case 2: remainder is type 'd' and type 'w': digits and other characters
     # Case 3: remainder is type 'w'

        # Examples, for $numc=1:
        #   $tok    => $tok_0 $tok_1 $tok_2
        #   'x10'   => 'x'    '10'                # case 1
        #   'x10if' => 'x'    '10'   'if'         # case 2
        #   '0ne    => 'O'            'ne'        # case 3

        # where:
        #   $tok_1 is a possible string of digits (pre-type 'd')
        #   $tok_2 is a possible word (pre-type 'w')

        # return 1 if successful
        # return undef if error (shouldn't happen)

        # Calling routine should update '$type' and '$tok' if successful.

        my $pretoken = $rtokens->[$i];
        if (   $pretoken
            && length($pretoken) > $numc
            && substr( $pretoken, $numc ) =~ /^(\d*)(.*)$/ )
        {

            # Split $tok into up to 3 tokens:
            my $tok_0 = substr( $pretoken, 0, $numc );
            my $tok_1 = defined($1) ? $1 : "";
            my $tok_2 = defined($2) ? $2 : "";

            my $len_0 = length($tok_0);
            my $len_1 = length($tok_1);
            my $len_2 = length($tok_2);

            my $pre_type_0 = 'w';
            my $pre_type_1 = 'd';
            my $pre_type_2 = 'w';

            my $pos_0 = $rtoken_map->[$i];
            my $pos_1 = $pos_0 + $len_0;
            my $pos_2 = $pos_1 + $len_1;

            my $isplice = $i + 1;

            # Splice in any digits
            if ($len_1) {
                splice @{$rtoken_map},  $isplice, 0, $pos_1;
                splice @{$rtokens},     $isplice, 0, $tok_1;
                splice @{$rtoken_type}, $isplice, 0, $pre_type_1;
                $max_token_index++;
                $isplice++;
            }

            # Splice in any trailing word
            if ($len_2) {
                splice @{$rtoken_map},  $isplice, 0, $pos_2;
                splice @{$rtokens},     $isplice, 0, $tok_2;
                splice @{$rtoken_type}, $isplice, 0, $pre_type_2;
                $max_token_index++;
            }

            $rtokens->[$i] = $tok_0;
            return 1;
        }
        else {

            # Shouldn't get here
            if (DEVEL_MODE) {
                Fault(<<EOM);
While working near line number $input_line_number, bad arg '$tok' passed to sub split_pretoken()
EOM
            }
        }
        return;
    }

    sub get_indentation_level {

        # patch to avoid reporting error if indented if is not terminated
        if ($indented_if_level) { return $level_in_tokenizer - 1 }
        return $level_in_tokenizer;
    }

    sub reset_indentation_level {
        $level_in_tokenizer = $slevel_in_tokenizer = shift;
        push @{$rslevel_stack}, $slevel_in_tokenizer;
        return;
    }

    sub peeked_ahead {
        my $flag = shift;
        $peeked_ahead = defined($flag) ? $flag : $peeked_ahead;
        return $peeked_ahead;
    }

    # ------------------------------------------------------------
    # end of tokenizer variable access and manipulation routines
    # ------------------------------------------------------------

    # ------------------------------------------------------------
    # beginning of various scanner interface routines
    # ------------------------------------------------------------
    sub scan_replacement_text {

        # check for here-docs in replacement text invoked by
        # a substitution operator with executable modifier 'e'.
        #
        # given:
        #  $replacement_text
        # return:
        #  $rht = reference to any here-doc targets
        my ($replacement_text) = @_;

        # quick check
        return unless ( $replacement_text =~ /<</ );

        write_logfile_entry("scanning replacement text for here-doc targets\n");

        # save the logger object for error messages
        my $logger_object = $tokenizer_self->[_logger_object_];

        # localize all package variables
        local (
            $tokenizer_self,                 $last_nonblank_token,
            $last_nonblank_type,             $last_nonblank_block_type,
            $statement_type,                 $in_attribute_list,
            $current_package,                $context,
            %is_constant,                    %is_user_function,
            %user_function_prototype,        %is_block_function,
            %is_block_list_function,         %saw_function_definition,
            $brace_depth,                    $paren_depth,
            $square_bracket_depth,           @current_depth,
            @total_depth,                    $total_depth,
            @nesting_sequence_number,        @current_sequence_number,
            @paren_type,                     @paren_semicolon_count,
            @paren_structural_type,          @brace_type,
            @brace_structural_type,          @brace_context,
            @brace_package,                  @square_bracket_type,
            @square_bracket_structural_type, @depth_array,
            @starting_line_of_current_depth, @nested_ternary_flag,
            @nested_statement_type,          $next_sequence_number,
        );

        # save all lexical variables
        my $rstate = save_tokenizer_state();
        _decrement_count();    # avoid error check for multiple tokenizers

        # make a new tokenizer
        my $rOpts = {};
        my $rpending_logfile_message;
        my $source_object = Perl::Tidy::LineSource->new(
            input_file               => \$replacement_text,
            rOpts                    => $rOpts,
            rpending_logfile_message => $rpending_logfile_message,
        );
        my $tokenizer = Perl::Tidy::Tokenizer->new(
            source_object        => $source_object,
            logger_object        => $logger_object,
            starting_line_number => $input_line_number,
        );

        # scan the replacement text
        1 while ( $tokenizer->get_line() );

        # remove any here doc targets
        my $rht = undef;
        if ( $tokenizer_self->[_in_here_doc_] ) {
            $rht = [];
            push @{$rht},
              [
                $tokenizer_self->[_here_doc_target_],
                $tokenizer_self->[_here_quote_character_]
              ];
            if ( $tokenizer_self->[_rhere_target_list_] ) {
                push @{$rht}, @{ $tokenizer_self->[_rhere_target_list_] };
                $tokenizer_self->[_rhere_target_list_] = undef;
            }
            $tokenizer_self->[_in_here_doc_] = undef;
        }

        # now its safe to report errors
        my $severe_error = $tokenizer->report_tokenization_errors();

        # TODO: Could propagate a severe error up

        # restore all tokenizer lexical variables
        restore_tokenizer_state($rstate);

        # return the here doc targets
        return $rht;
    }

    sub scan_bare_identifier {
        ( $i, $tok, $type, $prototype ) =
          scan_bare_identifier_do( $input_line, $i, $tok, $type, $prototype,
            $rtoken_map, $max_token_index );
        return;
    }

    sub scan_identifier {
        ( $i, $tok, $type, $id_scan_state, $identifier ) =
          scan_identifier_do( $i, $id_scan_state, $identifier, $rtokens,
            $max_token_index, $expecting, $paren_type[$paren_depth] );

        # Check for signal to fix a special variable adjacent to a keyword,
        # such as '$^One$0'.
        if ( $id_scan_state eq '^' ) {

            # Try to fix it by splitting the pretoken
            if (   $i > 0
                && $rtokens->[ $i - 1 ] eq '^'
                && split_pretoken(1) )
            {
                $identifier = substr( $identifier, 0, 3 );
                $tok        = $identifier;
            }
            else {

                # This shouldn't happen ...
                my $var    = substr( $tok, 0, 3 );
                my $excess = substr( $tok, 3 );
                interrupt_logfile();
                warning(<<EOM);
$input_line_number: Trouble parsing at characters '$excess' after special variable '$var'.
A space may be needed after '$var'. 
EOM
                resume_logfile();
            }
            $id_scan_state = "";
        }
        return;
    }

    use constant VERIFY_FASTSCAN => 0;
    my %fast_scan_context;

    BEGIN {
        %fast_scan_context = (
            '$' => SCALAR_CONTEXT,
            '*' => SCALAR_CONTEXT,
            '@' => LIST_CONTEXT,
            '%' => LIST_CONTEXT,
            '&' => UNKNOWN_CONTEXT,
        );
    }

    sub scan_identifier_fast {

        # This is a wrapper for sub scan_identifier. It does a fast preliminary
        # scan for certain common identifiers:
        #   '$var', '@var', %var, *var, &var, '@{...}', '%{...}'
        # If it does not find one of these, or this is a restart, it calls the
        # original scanner directly.

        # This gives the same results as the full scanner in about 1/4 the
        # total runtime for a typical input stream.

        my $i_begin   = $i;
        my $tok_begin = $tok;
        my $fast_scan_type;

        ###############################
        # quick scan with leading sigil
        ###############################
        if (  !$id_scan_state
            && $i + 1 <= $max_token_index
            && $fast_scan_context{$tok} )
        {
            $context = $fast_scan_context{$tok};

            # look for $var, @var, ...
            if ( $rtoken_type->[ $i + 1 ] eq 'w' ) {
                my $pretype_next = "";
                my $i_next       = $i + 2;
                if ( $i_next <= $max_token_index ) {
                    if (   $rtoken_type->[$i_next] eq 'b'
                        && $i_next < $max_token_index )
                    {
                        $i_next += 1;
                    }
                    $pretype_next = $rtoken_type->[$i_next];
                }
                if ( $pretype_next ne ':' && $pretype_next ne "'" ) {

                    # Found type 'i' like '$var', '@var', or '%var'
                    $identifier     = $tok . $rtokens->[ $i + 1 ];
                    $tok            = $identifier;
                    $type           = 'i';
                    $i              = $i + 1;
                    $fast_scan_type = $type;
                }
            }

            # Look for @{ or %{  .
            # But we must let the full scanner handle things ${ because it may
            # keep going to get a complete identifier like '${#}'  .
            elsif (
                $rtoken_type->[ $i + 1 ] eq '{'
                && (   $tok_begin eq '@'
                    || $tok_begin eq '%' )
              )
            {

                $identifier     = $tok;
                $type           = 't';
                $fast_scan_type = $type;
            }
        }

        ############################
        # Quick scan with leading ->
        # Look for ->[ and ->{
        ############################
        elsif (
               $tok eq '->'
            && $i < $max_token_index
            && (   $rtokens->[ $i + 1 ] eq '{'
                || $rtokens->[ $i + 1 ] eq '[' )
          )
        {
            $type           = $tok;
            $fast_scan_type = $type;
            $identifier     = $tok;
            $context        = UNKNOWN_CONTEXT;
        }

        #######################################
        # Verify correctness during development
        #######################################
        if ( VERIFY_FASTSCAN && $fast_scan_type ) {

            # We will call the full method
            my $identifier_simple = $identifier;
            my $tok_simple        = $tok;
            my $fast_scan_type    = $type;
            my $i_simple          = $i;
            my $context_simple    = $context;

            $tok = $tok_begin;
            $i   = $i_begin;
            scan_identifier();

            if (   $tok ne $tok_simple
                || $type ne $fast_scan_type
                || $i != $i_simple
                || $identifier ne $identifier_simple
                || $id_scan_state
                || $context ne $context_simple )
            {
                print STDERR <<EOM;
scan_identifier_fast differs from scan_identifier:
simple:  i=$i_simple, tok=$tok_simple, type=$fast_scan_type, ident=$identifier_simple, context='$context_simple
full:    i=$i, tok=$tok, type=$type, ident=$identifier, context='$context state=$id_scan_state
EOM
            }
        }

        ###################################################
        # call full scanner if fast method did not succeed
        ###################################################
        if ( !$fast_scan_type ) {
            scan_identifier();
        }
        return;
    }

    sub scan_id {
        ( $i, $tok, $type, $id_scan_state ) =
          scan_id_do( $input_line, $i, $tok, $rtokens, $rtoken_map,
            $id_scan_state, $max_token_index );
        return;
    }

    sub scan_number {
        my $number;
        ( $i, $type, $number ) =
          scan_number_do( $input_line, $i, $rtoken_map, $type,
            $max_token_index );
        return $number;
    }

    use constant VERIFY_FASTNUM => 0;

    sub scan_number_fast {

        # This is a wrapper for sub scan_number. It does a fast preliminary
        # scan for a simple integer.  It calls the original scan_number if it
        # does not find one.

        my $i_begin   = $i;
        my $tok_begin = $tok;
        my $number;

        ##################################
        # Quick check for (signed) integer
        ##################################

        # This will be the string of digits:
        my $i_d   = $i;
        my $tok_d = $tok;
        my $typ_d = $rtoken_type->[$i_d];

        # check for signed integer
        my $sign = "";
        if (   $typ_d ne 'd'
            && ( $typ_d eq '+' || $typ_d eq '-' )
            && $i_d < $max_token_index )
        {
            $sign = $tok_d;
            $i_d++;
            $tok_d = $rtokens->[$i_d];
            $typ_d = $rtoken_type->[$i_d];
        }

        # Handle integers
        if (
            $typ_d eq 'd'
            && (
                $i_d == $max_token_index
                || (   $i_d < $max_token_index
                    && $rtoken_type->[ $i_d + 1 ] ne '.'
                    && $rtoken_type->[ $i_d + 1 ] ne 'w' )
            )
          )
        {
            # Let let full scanner handle multi-digit integers beginning with
            # '0' because there could be error messages.  For example, '009' is
            # not a valid number.

            if ( $tok_d eq '0' || substr( $tok_d, 0, 1 ) ne '0' ) {
                $number = $sign . $tok_d;
                $type   = 'n';
                $i      = $i_d;
            }
        }

        #######################################
        # Verify correctness during development
        #######################################
        if ( VERIFY_FASTNUM && defined($number) ) {

            # We will call the full method
            my $type_simple   = $type;
            my $i_simple      = $i;
            my $number_simple = $number;

            $tok    = $tok_begin;
            $i      = $i_begin;
            $number = scan_number();

            if (   $type ne $type_simple
                || ( $i != $i_simple && $i <= $max_token_index )
                || $number ne $number_simple )
            {
                print STDERR <<EOM;
scan_number_fast differs from scan_number:
simple:  i=$i_simple, type=$type_simple, number=$number_simple
full:  i=$i, type=$type, number=$number
EOM
            }
        }

        #########################################
        # call full scanner if may not be integer
        #########################################
        if ( !defined($number) ) {
            $number = scan_number();
        }
        return $number;
    }

    # a sub to warn if token found where term expected
    sub error_if_expecting_TERM {
        if ( $expecting == TERM ) {
            if ( $really_want_term{$last_nonblank_type} ) {
                report_unexpected( $tok, "term", $i_tok, $last_nonblank_i,
                    $rtoken_map, $rtoken_type, $input_line );
                return 1;
            }
        }
        return;
    }

    # a sub to warn if token found where operator expected
    sub error_if_expecting_OPERATOR {
        my $thing = shift;
        if ( $expecting == OPERATOR ) {
            if ( !defined($thing) ) { $thing = $tok }
            report_unexpected( $thing, "operator", $i_tok, $last_nonblank_i,
                $rtoken_map, $rtoken_type, $input_line );
            if ( $i_tok == 0 ) {
                interrupt_logfile();
                warning("Missing ';' or ',' above?\n");
                resume_logfile();
            }
            return 1;
        }
        return;
    }

    # ------------------------------------------------------------
    # end scanner interfaces
    # ------------------------------------------------------------

    my %is_for_foreach;
    @_ = qw(for foreach);
    @is_for_foreach{@_} = (1) x scalar(@_);

    my %is_my_our_state;
    @_ = qw(my our state);
    @is_my_our_state{@_} = (1) x scalar(@_);

    # These keywords may introduce blocks after parenthesized expressions,
    # in the form:
    # keyword ( .... ) { BLOCK }
    # patch for SWITCH/CASE: added 'switch' 'case' 'given' 'when'
    my %is_blocktype_with_paren;
    @_ =
      qw(if elsif unless while until for foreach switch case given when catch);
    @is_blocktype_with_paren{@_} = (1) x scalar(@_);

    my %is_case_default;
    @_ = qw(case default);
    @is_case_default{@_} = (1) x scalar(@_);

    # ------------------------------------------------------------
    # begin hash of code for handling most token types
    # ------------------------------------------------------------
    my $tokenization_code = {

        # no special code for these types yet, but syntax checks
        # could be added

##      '!'   => undef,
##      '!='  => undef,
##      '!~'  => undef,
##      '%='  => undef,
##      '&&=' => undef,
##      '&='  => undef,
##      '+='  => undef,
##      '-='  => undef,
##      '..'  => undef,
##      '..'  => undef,
##      '...' => undef,
##      '.='  => undef,
##      '<<=' => undef,
##      '<='  => undef,
##      '<=>' => undef,
##      '<>'  => undef,
##      '='   => undef,
##      '=='  => undef,
##      '=~'  => undef,
##      '>='  => undef,
##      '>>'  => undef,
##      '>>=' => undef,
##      '\\'  => undef,
##      '^='  => undef,
##      '|='  => undef,
##      '||=' => undef,
##      '//=' => undef,
##      '~'   => undef,
##      '~~'  => undef,
##      '!~~'  => undef,

        '>' => sub {
            error_if_expecting_TERM()
              if ( $expecting == TERM );
        },
        '|' => sub {
            error_if_expecting_TERM()
              if ( $expecting == TERM );
        },
        '$' => sub {

            # start looking for a scalar
            error_if_expecting_OPERATOR("Scalar")
              if ( $expecting == OPERATOR );
            scan_identifier_fast();

            if ( $identifier eq '$^W' ) {
                $tokenizer_self->[_saw_perl_dash_w_] = 1;
            }

            # Check for identifier in indirect object slot
            # (vorboard.pl, sort.t).  Something like:
            #   /^(print|printf|sort|exec|system)$/
            if (
                $is_indirect_object_taker{$last_nonblank_token}
                || ( ( $last_nonblank_token eq '(' )
                    && $is_indirect_object_taker{ $paren_type[$paren_depth] } )
                || (   $last_nonblank_type eq 'w'
                    || $last_nonblank_type eq 'U' )    # possible object
              )
            {

                # An identifier followed by '->' is not indirect object;
                # fixes b1175, b1176
                my ( $next_nonblank_type, $i_next ) =
                  find_next_noncomment_type( $i, $rtokens, $max_token_index );
                $type = 'Z' if ( $next_nonblank_type ne '->' );
            }
        },
        '(' => sub {

            ++$paren_depth;
            $paren_semicolon_count[$paren_depth] = 0;
            if ($want_paren) {
                $container_type = $want_paren;
                $want_paren     = "";
            }
            elsif ( $statement_type =~ /^sub\b/ ) {
                $container_type = $statement_type;
            }
            else {
                $container_type = $last_nonblank_token;

                # We can check for a syntax error here of unexpected '(',
                # but this is going to get messy...
                if (
                    $expecting == OPERATOR

                    # Be sure this is not a method call of the form
                    # &method(...), $method->(..), &{method}(...),
                    # $ref[2](list) is ok & short for $ref[2]->(list)
                    # NOTE: at present, braces in something like &{ xxx }
                    # are not marked as a block, we might have a method call.
                    # Added ')' to fix case c017, something like ()()()
                    && $last_nonblank_token !~ /^([\]\}\)\&]|\-\>)/

                  )
                {

                    # ref: camel 3 p 703.
                    if ( $last_last_nonblank_token eq 'do' ) {
                        complain(
"do SUBROUTINE is deprecated; consider & or -> notation\n"
                        );
                    }
                    else {

                        # if this is an empty list, (), then it is not an
                        # error; for example, we might have a constant pi and
                        # invoke it with pi() or just pi;
                        my ( $next_nonblank_token, $i_next ) =
                          find_next_nonblank_token( $i, $rtokens,
                            $max_token_index );

                        # Patch for c029: give up error check if
                        # a side comment follows
                        if (   $next_nonblank_token ne ')'
                            && $next_nonblank_token ne '#' )
                        {
                            my $hint;

                            error_if_expecting_OPERATOR('(');

                            if ( $last_nonblank_type eq 'C' ) {
                                $hint =
                                  "$last_nonblank_token has a void prototype\n";
                            }
                            elsif ( $last_nonblank_type eq 'i' ) {
                                if (   $i_tok > 0
                                    && $last_nonblank_token =~ /^\$/ )
                                {
                                    $hint =
"Do you mean '$last_nonblank_token->(' ?\n";
                                }
                            }
                            if ($hint) {
                                interrupt_logfile();
                                warning($hint);
                                resume_logfile();
                            }
                        } ## end if ( $next_nonblank_token...
                    } ## end else [ if ( $last_last_nonblank_token...
                } ## end if ( $expecting == OPERATOR...
            }
            $paren_type[$paren_depth] = $container_type;
            ( $type_sequence, $indent_flag ) =
              increase_nesting_depth( PAREN, $rtoken_map->[$i_tok] );

            # propagate types down through nested parens
            # for example: the second paren in 'if ((' would be structural
            # since the first is.

            if ( $last_nonblank_token eq '(' ) {
                $type = $last_nonblank_type;
            }

            #     We exclude parens as structural after a ',' because it
            #     causes subtle problems with continuation indentation for
            #     something like this, where the first 'or' will not get
            #     indented.
            #
            #         assert(
            #             __LINE__,
            #             ( not defined $check )
            #               or ref $check
            #               or $check eq "new"
            #               or $check eq "old",
            #         );
            #
            #     Likewise, we exclude parens where a statement can start
            #     because of problems with continuation indentation, like
            #     these:
            #
            #         ($firstline =~ /^#\!.*perl/)
            #         and (print $File::Find::name, "\n")
            #           and (return 1);
            #
            #         (ref($usage_fref) =~ /CODE/)
            #         ? &$usage_fref
            #           : (&blast_usage, &blast_params, &blast_general_params);

            else {
                $type = '{';
            }

            if ( $last_nonblank_type eq ')' ) {
                warning(
                    "Syntax error? found token '$last_nonblank_type' then '('\n"
                );
            }
            $paren_structural_type[$paren_depth] = $type;

        },
        ')' => sub {
            ( $type_sequence, $indent_flag ) =
              decrease_nesting_depth( PAREN, $rtoken_map->[$i_tok] );

            if ( $paren_structural_type[$paren_depth] eq '{' ) {
                $type = '}';
            }

            $container_type = $paren_type[$paren_depth];

            # restore statement type as 'sub' at closing paren of a signature
            # so that a subsequent ':' is identified as an attribute
            if ( $container_type =~ /^sub\b/ ) {
                $statement_type = $container_type;
            }

            #    /^(for|foreach)$/
            if ( $is_for_foreach{ $paren_type[$paren_depth] } ) {
                my $num_sc = $paren_semicolon_count[$paren_depth];
                if ( $num_sc > 0 && $num_sc != 2 ) {
                    warning("Expected 2 ';' in 'for(;;)' but saw $num_sc\n");
                }
            }

            if ( $paren_depth > 0 ) { $paren_depth-- }
        },
        ',' => sub {
            if ( $last_nonblank_type eq ',' ) {
                complain("Repeated ','s \n");
            }

            # Note that we have to check both token and type here because a
            # comma following a qw list can have last token='(' but type = 'q'
            elsif ( $last_nonblank_token eq '(' && $last_nonblank_type eq '{' )
            {
                warning("Unexpected leading ',' after a '('\n");
            }

            # patch for operator_expected: note if we are in the list (use.t)
            if ( $statement_type eq 'use' ) { $statement_type = '_use' }

        },
        ';' => sub {
            $context        = UNKNOWN_CONTEXT;
            $statement_type = '';
            $want_paren     = "";

            #    /^(for|foreach)$/
            if ( $is_for_foreach{ $paren_type[$paren_depth] } )
            {    # mark ; in for loop

                # Be careful: we do not want a semicolon such as the
                # following to be included:
                #
                #    for (sort {strcoll($a,$b);} keys %investments) {

                if (   $brace_depth == $depth_array[PAREN][BRACE][$paren_depth]
                    && $square_bracket_depth ==
                    $depth_array[PAREN][SQUARE_BRACKET][$paren_depth] )
                {

                    $type = 'f';
                    $paren_semicolon_count[$paren_depth]++;
                }
            }

        },
        '"' => sub {
            error_if_expecting_OPERATOR("String")
              if ( $expecting == OPERATOR );
            $in_quote                = 1;
            $type                    = 'Q';
            $allowed_quote_modifiers = "";
        },
        "'" => sub {
            error_if_expecting_OPERATOR("String")
              if ( $expecting == OPERATOR );
            $in_quote                = 1;
            $type                    = 'Q';
            $allowed_quote_modifiers = "";
        },
        '`' => sub {
            error_if_expecting_OPERATOR("String")
              if ( $expecting == OPERATOR );
            $in_quote                = 1;
            $type                    = 'Q';
            $allowed_quote_modifiers = "";
        },
        '/' => sub {
            my $is_pattern;

            # a pattern cannot follow certain keywords which take optional
            # arguments, like 'shift' and 'pop'. See also '?'.
            if (
                $last_nonblank_type eq 'k'
                && $is_keyword_rejecting_slash_as_pattern_delimiter{
                    $last_nonblank_token}
              )
            {
                $is_pattern = 0;
            }
            elsif ( $expecting == UNKNOWN ) {    # indeterminate, must guess..
                my $msg;
                ( $is_pattern, $msg ) =
                  guess_if_pattern_or_division( $i, $rtokens, $rtoken_map,
                    $max_token_index );

                if ($msg) {
                    write_diagnostics("DIVIDE:$msg\n");
                    write_logfile_entry($msg);
                }
            }
            else { $is_pattern = ( $expecting == TERM ) }

            if ($is_pattern) {
                $in_quote                = 1;
                $type                    = 'Q';
                $allowed_quote_modifiers = '[msixpodualngc]';
            }
            else {    # not a pattern; check for a /= token

                if ( $rtokens->[ $i + 1 ] eq '=' ) {    # form token /=
                    $i++;
                    $tok  = '/=';
                    $type = $tok;
                }

           #DEBUG - collecting info on what tokens follow a divide
           # for development of guessing algorithm
           #if ( is_possible_numerator( $i, $rtokens, $max_token_index ) < 0 ) {
           #    #write_diagnostics( "DIVIDE? $input_line\n" );
           #}
            }
        },
        '{' => sub {

            # if we just saw a ')', we will label this block with
            # its type.  We need to do this to allow sub
            # code_block_type to determine if this brace starts a
            # code block or anonymous hash.  (The type of a paren
            # pair is the preceding token, such as 'if', 'else',
            # etc).
            $container_type = "";

            # ATTRS: for a '{' following an attribute list, reset
            # things to look like we just saw the sub name
            if ( $statement_type =~ /^sub\b/ ) {
                $last_nonblank_token = $statement_type;
                $last_nonblank_type  = 'i';
                $statement_type      = "";
            }

            # patch for SWITCH/CASE: hide these keywords from an immediately
            # following opening brace
            elsif ( ( $statement_type eq 'case' || $statement_type eq 'when' )
                && $statement_type eq $last_nonblank_token )
            {
                $last_nonblank_token = ";";
            }

            elsif ( $last_nonblank_token eq ')' ) {
                $last_nonblank_token = $paren_type[ $paren_depth + 1 ];

                # defensive move in case of a nesting error (pbug.t)
                # in which this ')' had no previous '('
                # this nesting error will have been caught
                if ( !defined($last_nonblank_token) ) {
                    $last_nonblank_token = 'if';
                }

                # check for syntax error here;
                unless ( $is_blocktype_with_paren{$last_nonblank_token} ) {
                    if ( $tokenizer_self->[_extended_syntax_] ) {

                        # we append a trailing () to mark this as an unknown
                        # block type.  This allows perltidy to format some
                        # common extensions of perl syntax.
                        # This is used by sub code_block_type
                        $last_nonblank_token .= '()';
                    }
                    else {
                        my $list =
                          join( ' ', sort keys %is_blocktype_with_paren );
                        warning(
"syntax error at ') {', didn't see one of: <<$list>>; If this code is okay try using the -xs flag\n"
                        );
                    }
                }
            }

            # patch for paren-less for/foreach glitch, part 2.
            # see note below under 'qw'
            elsif ($last_nonblank_token eq 'qw'
                && $is_for_foreach{$want_paren} )
            {
                $last_nonblank_token = $want_paren;
                if ( $last_last_nonblank_token eq $want_paren ) {
                    warning(
"syntax error at '$want_paren .. {' -- missing \$ loop variable\n"
                    );

                }
                $want_paren = "";
            }

            # now identify which of the three possible types of
            # curly braces we have: hash index container, anonymous
            # hash reference, or code block.

            # non-structural (hash index) curly brace pair
            # get marked 'L' and 'R'
            if ( is_non_structural_brace() ) {
                $type = 'L';

                # patch for SWITCH/CASE:
                # allow paren-less identifier after 'when'
                # if the brace is preceded by a space
                if (   $statement_type eq 'when'
                    && $last_nonblank_type eq 'i'
                    && $last_last_nonblank_type eq 'k'
                    && ( $i_tok == 0 || $rtoken_type->[ $i_tok - 1 ] eq 'b' ) )
                {
                    $type       = '{';
                    $block_type = $statement_type;
                }
            }

            # code and anonymous hash have the same type, '{', but are
            # distinguished by 'block_type',
            # which will be blank for an anonymous hash
            else {

                $block_type = code_block_type( $i_tok, $rtokens, $rtoken_type,
                    $max_token_index );

                # patch to promote bareword type to function taking block
                if (   $block_type
                    && $last_nonblank_type eq 'w'
                    && $last_nonblank_i >= 0 )
                {
                    if ( $routput_token_type->[$last_nonblank_i] eq 'w' ) {
                        $routput_token_type->[$last_nonblank_i] =
                          $is_grep_alias{$block_type} ? 'k' : 'G';
                    }
                }

                # patch for SWITCH/CASE: if we find a stray opening block brace
                # where we might accept a 'case' or 'when' block, then take it
                if (   $statement_type eq 'case'
                    || $statement_type eq 'when' )
                {
                    if ( !$block_type || $block_type eq '}' ) {
                        $block_type = $statement_type;
                    }
                }
            }

            $brace_type[ ++$brace_depth ]        = $block_type;
            $brace_package[$brace_depth]         = $current_package;
            $brace_structural_type[$brace_depth] = $type;
            $brace_context[$brace_depth]         = $context;
            ( $type_sequence, $indent_flag ) =
              increase_nesting_depth( BRACE, $rtoken_map->[$i_tok] );
        },
        '}' => sub {
            $block_type = $brace_type[$brace_depth];
            if ($block_type) { $statement_type = '' }
            if ( defined( $brace_package[$brace_depth] ) ) {
                $current_package = $brace_package[$brace_depth];
            }

            # can happen on brace error (caught elsewhere)
            else {
            }
            ( $type_sequence, $indent_flag ) =
              decrease_nesting_depth( BRACE, $rtoken_map->[$i_tok] );

            if ( $brace_structural_type[$brace_depth] eq 'L' ) {
                $type = 'R';
            }

            # propagate type information for 'do' and 'eval' blocks, and also
            # for smartmatch operator.  This is necessary to enable us to know
            # if an operator or term is expected next.
            if ( $is_block_operator{$block_type} ) {
                $tok = $block_type;
            }

            $context = $brace_context[$brace_depth];
            if ( $brace_depth > 0 ) { $brace_depth--; }
        },
        '&' => sub {    # maybe sub call? start looking

            # We have to check for sub call unless we are sure we
            # are expecting an operator.  This example from s2p
            # got mistaken as a q operator in an early version:
            #   print BODY &q(<<'EOT');
            if ( $expecting != OPERATOR ) {

                # But only look for a sub call if we are expecting a term or
                # if there is no existing space after the &.
                # For example we probably don't want & as sub call here:
                #    Fcntl::S_IRUSR & $mode;
                if ( $expecting == TERM || $next_type ne 'b' ) {
                    scan_identifier_fast();
                }
            }
            else {
            }
        },
        '<' => sub {    # angle operator or less than?

            if ( $expecting != OPERATOR ) {
                ( $i, $type ) =
                  find_angle_operator_termination( $input_line, $i, $rtoken_map,
                    $expecting, $max_token_index );

                ##  This message is not very helpful and quite confusing if the above
                ##  routine decided not to write a message with the line number.
                ##  if ( $type eq '<' && $expecting == TERM ) {
                ##      error_if_expecting_TERM();
                ##      interrupt_logfile();
                ##      warning("Unterminated <> operator?\n");
                ##      resume_logfile();
                ##  }

            }
            else {
            }
        },
        '?' => sub {    # ?: conditional or starting pattern?

            my $is_pattern;

            # Patch for rt #126965
            # a pattern cannot follow certain keywords which take optional
            # arguments, like 'shift' and 'pop'. See also '/'.
            if (
                $last_nonblank_type eq 'k'
                && $is_keyword_rejecting_question_as_pattern_delimiter{
                    $last_nonblank_token}
              )
            {
                $is_pattern = 0;
            }

            # patch for RT#131288, user constant function without prototype
            # last type is 'U' followed by ?.
            elsif ( $last_nonblank_type =~ /^[FUY]$/ ) {
                $is_pattern = 0;
            }
            elsif ( $expecting == UNKNOWN ) {

                # In older versions of Perl, a bare ? can be a pattern
                # delimiter.  In perl version 5.22 this was
                # dropped, but we have to support it in order to format
                # older programs. See:
                ## https://perl.developpez.com/documentations/en/5.22.0/perl5211delta.html
                # For example, the following line worked
                # at one time:
                #      ?(.*)? && (print $1,"\n");
                # In current versions it would have to be written with slashes:
                #      /(.*)/ && (print $1,"\n");
                my $msg;
                ( $is_pattern, $msg ) =
                  guess_if_pattern_or_conditional( $i, $rtokens, $rtoken_map,
                    $max_token_index );

                if ($msg) { write_logfile_entry($msg) }
            }
            else { $is_pattern = ( $expecting == TERM ) }

            if ($is_pattern) {
                $in_quote                = 1;
                $type                    = 'Q';
                $allowed_quote_modifiers = '[msixpodualngc]';
            }
            else {
                ( $type_sequence, $indent_flag ) =
                  increase_nesting_depth( QUESTION_COLON,
                    $rtoken_map->[$i_tok] );
            }
        },
        '*' => sub {    # typeglob, or multiply?

            if ( $expecting == UNKNOWN && $last_nonblank_type eq 'Z' ) {
                if (   $next_type ne 'b'
                    && $next_type ne '('
                    && $next_type ne '#' )    # Fix c036
                {
                    $expecting = TERM;
                }
            }
            if ( $expecting == TERM ) {
                scan_identifier_fast();
            }
            else {

                if ( $rtokens->[ $i + 1 ] eq '=' ) {
                    $tok  = '*=';
                    $type = $tok;
                    $i++;
                }
                elsif ( $rtokens->[ $i + 1 ] eq '*' ) {
                    $tok  = '**';
                    $type = $tok;
                    $i++;
                    if ( $rtokens->[ $i + 1 ] eq '=' ) {
                        $tok  = '**=';
                        $type = $tok;
                        $i++;
                    }
                }
            }
        },
        '.' => sub {    # what kind of . ?

            if ( $expecting != OPERATOR ) {
                scan_number();
                if ( $type eq '.' ) {
                    error_if_expecting_TERM()
                      if ( $expecting == TERM );
                }
            }
            else {
            }
        },
        ':' => sub {

            # if this is the first nonblank character, call it a label
            # since perl seems to just swallow it
            if ( $input_line_number == 1 && $last_nonblank_i == -1 ) {
                $type = 'J';
            }

            # ATTRS: check for a ':' which introduces an attribute list
            # either after a 'sub' keyword or within a paren list
            elsif ( $statement_type =~ /^sub\b/ ) {
                $type              = 'A';
                $in_attribute_list = 1;
            }

            # Within a signature, unless we are in a ternary.  For example,
            # from 't/filter_example.t':
            #    method foo4 ( $class: $bar ) { $class->bar($bar) }
            elsif ( $paren_type[$paren_depth] =~ /^sub\b/
                && !is_balanced_closing_container(QUESTION_COLON) )
            {
                $type              = 'A';
                $in_attribute_list = 1;
            }

            # check for scalar attribute, such as
            # my $foo : shared = 1;
            elsif ($is_my_our_state{$statement_type}
                && $current_depth[QUESTION_COLON] == 0 )
            {
                $type              = 'A';
                $in_attribute_list = 1;
            }

            # Look for Switch::Plain syntax if an error would otherwise occur
            # here. Note that we do not need to check if the extended syntax
            # flag is set because otherwise an error would occur, and we would
            # then have to output a message telling the user to set the
            # extended syntax flag to avoid the error.
            #  case 1: {
            #  default: {
            #  default:
            # Note that the line 'default:' will be parsed as a label elsewhere.
            elsif ( $is_case_default{$statement_type}
                && !is_balanced_closing_container(QUESTION_COLON) )
            {
                # mark it as a perltidy label type
                $type = 'J';
            }

            # otherwise, it should be part of a ?/: operator
            else {
                ( $type_sequence, $indent_flag ) =
                  decrease_nesting_depth( QUESTION_COLON,
                    $rtoken_map->[$i_tok] );
                if ( $last_nonblank_token eq '?' ) {
                    warning("Syntax error near ? :\n");
                }
            }
        },
        '+' => sub {    # what kind of plus?

            if ( $expecting == TERM ) {
                my $number = scan_number_fast();

                # unary plus is safest assumption if not a number
                if ( !defined($number) ) { $type = 'p'; }
            }
            elsif ( $expecting == OPERATOR ) {
            }
            else {
                if ( $next_type eq 'w' ) { $type = 'p' }
            }
        },
        '@' => sub {

            error_if_expecting_OPERATOR("Array")
              if ( $expecting == OPERATOR );
            scan_identifier_fast();
        },
        '%' => sub {    # hash or modulo?

            # first guess is hash if no following blank or paren
            if ( $expecting == UNKNOWN ) {
                if ( $next_type ne 'b' && $next_type ne '(' ) {
                    $expecting = TERM;
                }
            }
            if ( $expecting == TERM ) {
                scan_identifier_fast();
            }
        },
        '[' => sub {
            $square_bracket_type[ ++$square_bracket_depth ] =
              $last_nonblank_token;
            ( $type_sequence, $indent_flag ) =
              increase_nesting_depth( SQUARE_BRACKET, $rtoken_map->[$i_tok] );

            # It may seem odd, but structural square brackets have
            # type '{' and '}'.  This simplifies the indentation logic.
            if ( !is_non_structural_brace() ) {
                $type = '{';
            }
            $square_bracket_structural_type[$square_bracket_depth] = $type;
        },
        ']' => sub {
            ( $type_sequence, $indent_flag ) =
              decrease_nesting_depth( SQUARE_BRACKET, $rtoken_map->[$i_tok] );

            if ( $square_bracket_structural_type[$square_bracket_depth] eq '{' )
            {
                $type = '}';
            }

            # propagate type information for smartmatch operator.  This is
            # necessary to enable us to know if an operator or term is expected
            # next.
            if ( $square_bracket_type[$square_bracket_depth] eq '~~' ) {
                $tok = $square_bracket_type[$square_bracket_depth];
            }

            if ( $square_bracket_depth > 0 ) { $square_bracket_depth--; }
        },
        '-' => sub {    # what kind of minus?

            if ( ( $expecting != OPERATOR )
                && $is_file_test_operator{$next_tok} )
            {
                my ( $next_nonblank_token, $i_next ) =
                  find_next_nonblank_token( $i + 1, $rtokens,
                    $max_token_index );

                # check for a quoted word like "-w=>xx";
                # it is sufficient to just check for a following '='
                if ( $next_nonblank_token eq '=' ) {
                    $type = 'm';
                }
                else {
                    $i++;
                    $tok .= $next_tok;
                    $type = 'F';
                }
            }
            elsif ( $expecting == TERM ) {
                my $number = scan_number_fast();

                # maybe part of bareword token? unary is safest
                if ( !defined($number) ) { $type = 'm'; }

            }
            elsif ( $expecting == OPERATOR ) {
            }
            else {

                if ( $next_type eq 'w' ) {
                    $type = 'm';
                }
            }
        },

        '^' => sub {

            # check for special variables like ${^WARNING_BITS}
            if ( $expecting == TERM ) {

                if (   $last_nonblank_token eq '{'
                    && ( $next_tok !~ /^\d/ )
                    && ( $next_tok =~ /^\w/ ) )
                {

                    if ( $next_tok eq 'W' ) {
                        $tokenizer_self->[_saw_perl_dash_w_] = 1;
                    }
                    $tok  = $tok . $next_tok;
                    $i    = $i + 1;
                    $type = 'w';

                    # Optional coding to try to catch syntax errors. This can
                    # be removed if it ever causes incorrect warning messages.
                    # The '{^' should be preceded by either by a type or '$#'
                    # Examples:
                    #   $#{^CAPTURE}       ok
                    #   *${^LAST_FH}{NAME} ok
                    #   @{^HOWDY}          ok
                    #   $hash{^HOWDY}      error

                    # Note that a type sigil '$' may be tokenized as 'Z'
                    # after something like 'print', so allow type 'Z'
                    if (   $last_last_nonblank_type ne 't'
                        && $last_last_nonblank_type ne 'Z'
                        && $last_last_nonblank_token ne '$#' )
                    {
                        warning("Possible syntax error near '{^'\n");
                    }
                }

                else {
                    unless ( error_if_expecting_TERM() ) {

                        # Something like this is valid but strange:
                        # undef ^I;
                        complain("The '^' seems unusual here\n");
                    }
                }
            }
        },

        '::' => sub {    # probably a sub call
            scan_bare_identifier();
        },
        '<<' => sub {    # maybe a here-doc?

##      This check removed because it could be a deprecated here-doc with
##      no specified target.  See example in log 16 Sep 2020.
##            return
##              unless ( $i < $max_token_index )
##              ;          # here-doc not possible if end of line

            if ( $expecting != OPERATOR ) {
                my ( $found_target, $here_doc_target, $here_quote_character,
                    $saw_error );
                (
                    $found_target, $here_doc_target, $here_quote_character, $i,
                    $saw_error
                  )
                  = find_here_doc( $expecting, $i, $rtokens, $rtoken_map,
                    $max_token_index );

                if ($found_target) {
                    push @{$rhere_target_list},
                      [ $here_doc_target, $here_quote_character ];
                    $type = 'h';
                    if ( length($here_doc_target) > 80 ) {
                        my $truncated = substr( $here_doc_target, 0, 80 );
                        complain("Long here-target: '$truncated' ...\n");
                    }
                    elsif ( !$here_doc_target ) {
                        warning(
                            'Use of bare << to mean <<"" is deprecated' . "\n" )
                          unless ($here_quote_character);
                    }
                    elsif ( $here_doc_target !~ /^[A-Z_]\w+$/ ) {
                        complain(
                            "Unconventional here-target: '$here_doc_target'\n");
                    }
                }
                elsif ( $expecting == TERM ) {
                    unless ($saw_error) {

                        # shouldn't happen..arriving here implies an error in
                        # the logic in sub 'find_here_doc'
                        if (DEVEL_MODE) {
                            Fault(<<EOM);
Program bug; didn't find here doc target
EOM
                        }
                        warning(
"Possible program error: didn't find here doc target\n"
                        );
                        report_definite_bug();
                    }
                }
            }
            else {
            }
        },
        '<<~' => sub {    # a here-doc, new type added in v26
            return
              unless ( $i < $max_token_index )
              ;           # here-doc not possible if end of line
            if ( $expecting != OPERATOR ) {
                my ( $found_target, $here_doc_target, $here_quote_character,
                    $saw_error );
                (
                    $found_target, $here_doc_target, $here_quote_character, $i,
                    $saw_error
                  )
                  = find_here_doc( $expecting, $i, $rtokens, $rtoken_map,
                    $max_token_index );

                if ($found_target) {

                    if ( length($here_doc_target) > 80 ) {
                        my $truncated = substr( $here_doc_target, 0, 80 );
                        complain("Long here-target: '$truncated' ...\n");
                    }
                    elsif ( $here_doc_target !~ /^[A-Z_]\w+$/ ) {
                        complain(
                            "Unconventional here-target: '$here_doc_target'\n");
                    }

                    # Note that we put a leading space on the here quote
                    # character indicate that it may be preceded by spaces
                    $here_quote_character = " " . $here_quote_character;
                    push @{$rhere_target_list},
                      [ $here_doc_target, $here_quote_character ];
                    $type = 'h';
                }
                elsif ( $expecting == TERM ) {
                    unless ($saw_error) {

                        # shouldn't happen..arriving here implies an error in
                        # the logic in sub 'find_here_doc'
                        if (DEVEL_MODE) {
                            Fault(<<EOM);
Program bug; didn't find here doc target
EOM
                        }
                        warning(
"Possible program error: didn't find here doc target\n"
                        );
                        report_definite_bug();
                    }
                }
            }
            else {
            }
        },
        '->' => sub {

            # if -> points to a bare word, we must scan for an identifier,
            # otherwise something like ->y would look like the y operator

            # NOTE: this will currently allow things like
            #     '->@array'    '->*VAR'  '->%hash'
            # to get parsed as identifiers, even though these are not currently
            # allowed syntax.  To catch syntax errors like this we could first
            # check that the next character and skip this call if it is one of
            # ' @ % * '.  A disadvantage with doing this is that this would
            # have to be fixed if the perltidy syntax is ever extended to make
            # any of these valid.  So for now this check is not done.
            scan_identifier_fast();
        },

        # type = 'pp' for pre-increment, '++' for post-increment
        '++' => sub {
            if    ( $expecting == TERM ) { $type = 'pp' }
            elsif ( $expecting == UNKNOWN ) {

                my ( $next_nonblank_token, $i_next ) =
                  find_next_nonblank_token( $i, $rtokens, $max_token_index );

                # Fix for c042: look past a side comment
                if ( $next_nonblank_token eq '#' ) {
                    ( $next_nonblank_token, $i_next ) =
                      find_next_nonblank_token( $max_token_index,
                        $rtokens, $max_token_index );
                }

                if ( $next_nonblank_token eq '$' ) { $type = 'pp' }
            }
        },

        '=>' => sub {
            if ( $last_nonblank_type eq $tok ) {
                complain("Repeated '=>'s \n");
            }

            # patch for operator_expected: note if we are in the list (use.t)
            # TODO: make version numbers a new token type
            if ( $statement_type eq 'use' ) { $statement_type = '_use' }
        },

        # type = 'mm' for pre-decrement, '--' for post-decrement
        '--' => sub {

            if    ( $expecting == TERM ) { $type = 'mm' }
            elsif ( $expecting == UNKNOWN ) {
                my ( $next_nonblank_token, $i_next ) =
                  find_next_nonblank_token( $i, $rtokens, $max_token_index );

                # Fix for c042: look past a side comment
                if ( $next_nonblank_token eq '#' ) {
                    ( $next_nonblank_token, $i_next ) =
                      find_next_nonblank_token( $max_token_index,
                        $rtokens, $max_token_index );
                }

                if ( $next_nonblank_token eq '$' ) { $type = 'mm' }
            }
        },

        '&&' => sub {
            error_if_expecting_TERM()
              if ( $expecting == TERM && $last_nonblank_token ne ',' );    #c015
        },

        '||' => sub {
            error_if_expecting_TERM()
              if ( $expecting == TERM && $last_nonblank_token ne ',' );    #c015
        },

        '//' => sub {
            error_if_expecting_TERM()
              if ( $expecting == TERM );
        },
    };

    # ------------------------------------------------------------
    # end hash of code for handling individual token types
    # ------------------------------------------------------------

    my %matching_start_token = ( '}' => '{', ']' => '[', ')' => '(' );

    # These block types terminate statements and do not need a trailing
    # semicolon
    # patched for SWITCH/CASE/
    my %is_zero_continuation_block_type;
    @_ = qw( } { BEGIN END CHECK INIT AUTOLOAD DESTROY UNITCHECK continue ;
      if elsif else unless while until for foreach switch case given when);
    @is_zero_continuation_block_type{@_} = (1) x scalar(@_);

    my %is_logical_container;
    @_ = qw(if elsif unless while and or err not && !  || for foreach);
    @is_logical_container{@_} = (1) x scalar(@_);

    my %is_binary_type;
    @_ = qw(|| &&);
    @is_binary_type{@_} = (1) x scalar(@_);

    my %is_binary_keyword;
    @_ = qw(and or err eq ne cmp);
    @is_binary_keyword{@_} = (1) x scalar(@_);

    # 'L' is token for opening { at hash key
    my %is_opening_type;
    @_ = qw< L { ( [ >;
    @is_opening_type{@_} = (1) x scalar(@_);

    # 'R' is token for closing } at hash key
    my %is_closing_type;
    @_ = qw< R } ) ] >;
    @is_closing_type{@_} = (1) x scalar(@_);

    my %is_redo_last_next_goto;
    @_ = qw(redo last next goto);
    @is_redo_last_next_goto{@_} = (1) x scalar(@_);

    my %is_use_require;
    @_ = qw(use require);
    @is_use_require{@_} = (1) x scalar(@_);

    # This hash holds the array index in $tokenizer_self for these keywords:
    # Fix for issue c035: removed 'format' from this hash
    my %is_END_DATA = (
        '__END__'  => _in_end_,
        '__DATA__' => _in_data_,
    );

    # original ref: camel 3 p 147,
    # but perl may accept undocumented flags
    # perl 5.10 adds 'p' (preserve)
    # Perl version 5.22 added 'n'
    # From http://perldoc.perl.org/perlop.html we have
    # /PATTERN/msixpodualngc or m?PATTERN?msixpodualngc
    # s/PATTERN/REPLACEMENT/msixpodualngcer
    # y/SEARCHLIST/REPLACEMENTLIST/cdsr
    # tr/SEARCHLIST/REPLACEMENTLIST/cdsr
    # qr/STRING/msixpodualn
    my %quote_modifiers = (
        's'  => '[msixpodualngcer]',
        'y'  => '[cdsr]',
        'tr' => '[cdsr]',
        'm'  => '[msixpodualngc]',
        'qr' => '[msixpodualn]',
        'q'  => "",
        'qq' => "",
        'qw' => "",
        'qx' => "",
    );

    # table showing how many quoted things to look for after quote operator..
    # s, y, tr have 2 (pattern and replacement)
    # others have 1 (pattern only)
    my %quote_items = (
        's'  => 2,
        'y'  => 2,
        'tr' => 2,
        'm'  => 1,
        'qr' => 1,
        'q'  => 1,
        'qq' => 1,
        'qw' => 1,
        'qx' => 1,
    );

    use constant DEBUG_TOKENIZE => 0;

    sub tokenize_this_line {

  # This routine breaks a line of perl code into tokens which are of use in
  # indentation and reformatting.  One of my goals has been to define tokens
  # such that a newline may be inserted between any pair of tokens without
  # changing or invalidating the program. This version comes close to this,
  # although there are necessarily a few exceptions which must be caught by
  # the formatter.  Many of these involve the treatment of bare words.
  #
  # The tokens and their types are returned in arrays.  See previous
  # routine for their names.
  #
  # See also the array "valid_token_types" in the BEGIN section for an
  # up-to-date list.
  #
  # To simplify things, token types are either a single character, or they
  # are identical to the tokens themselves.
  #
  # As a debugging aid, the -D flag creates a file containing a side-by-side
  # comparison of the input string and its tokenization for each line of a file.
  # This is an invaluable debugging aid.
  #
  # In addition to tokens, and some associated quantities, the tokenizer
  # also returns flags indication any special line types.  These include
  # quotes, here_docs, formats.
  #
  # -----------------------------------------------------------------------
  #
  # How to add NEW_TOKENS:
  #
  # New token types will undoubtedly be needed in the future both to keep up
  # with changes in perl and to help adapt the tokenizer to other applications.
  #
  # Here are some notes on the minimal steps.  I wrote these notes while
  # adding the 'v' token type for v-strings, which are things like version
  # numbers 5.6.0, and ip addresses, and will use that as an example.  ( You
  # can use your editor to search for the string "NEW_TOKENS" to find the
  # appropriate sections to change):
  #
  # *. Try to talk somebody else into doing it!  If not, ..
  #
  # *. Make a backup of your current version in case things don't work out!
  #
  # *. Think of a new, unused character for the token type, and add to
  # the array @valid_token_types in the BEGIN section of this package.
  # For example, I used 'v' for v-strings.
  #
  # *. Implement coding to recognize the $type of the token in this routine.
  # This is the hardest part, and is best done by imitating or modifying
  # some of the existing coding.  For example, to recognize v-strings, I
  # patched 'sub scan_bare_identifier' to recognize v-strings beginning with
  # 'v' and 'sub scan_number' to recognize v-strings without the leading 'v'.
  #
  # *. Update sub operator_expected.  This update is critically important but
  # the coding is trivial.  Look at the comments in that routine for help.
  # For v-strings, which should behave like numbers, I just added 'v' to the
  # regex used to handle numbers and strings (types 'n' and 'Q').
  #
  # *. Implement a 'bond strength' rule in sub set_bond_strengths in
  # Perl::Tidy::Formatter for breaking lines around this token type.  You can
  # skip this step and take the default at first, then adjust later to get
  # desired results.  For adding type 'v', I looked at sub bond_strength and
  # saw that number type 'n' was using default strengths, so I didn't do
  # anything.  I may tune it up someday if I don't like the way line
  # breaks with v-strings look.
  #
  # *. Implement a 'whitespace' rule in sub set_whitespace_flags in
  # Perl::Tidy::Formatter.  For adding type 'v', I looked at this routine
  # and saw that type 'n' used spaces on both sides, so I just added 'v'
  # to the array @spaces_both_sides.
  #
  # *. Update HtmlWriter package so that users can colorize the token as
  # desired.  This is quite easy; see comments identified by 'NEW_TOKENS' in
  # that package.  For v-strings, I initially chose to use a default color
  # equal to the default for numbers, but it might be nice to change that
  # eventually.
  #
  # *. Update comments in Perl::Tidy::Tokenizer::dump_token_types.
  #
  # *. Run lots and lots of debug tests.  Start with special files designed
  # to test the new token type.  Run with the -D flag to create a .DEBUG
  # file which shows the tokenization.  When these work ok, test as many old
  # scripts as possible.  Start with all of the '.t' files in the 'test'
  # directory of the distribution file.  Compare .tdy output with previous
  # version and updated version to see the differences.  Then include as
  # many more files as possible. My own technique has been to collect a huge
  # number of perl scripts (thousands!) into one directory and run perltidy
  # *, then run diff between the output of the previous version and the
  # current version.
  #
  # *. For another example, search for the smartmatch operator '~~'
  # with your editor to see where updates were made for it.
  #
  # -----------------------------------------------------------------------

        my $line_of_tokens = shift;
        my ($untrimmed_input_line) = $line_of_tokens->{_line_text};

        # patch while coding change is underway
        # make callers private data to allow access
        # $tokenizer_self = $caller_tokenizer_self;

        # extract line number for use in error messages
        $input_line_number = $line_of_tokens->{_line_number};

        # reinitialize for multi-line quote
        $line_of_tokens->{_starting_in_quote} = $in_quote && $quote_type eq 'Q';

        # check for pod documentation
        if ( substr( $untrimmed_input_line, 0, 1 ) eq '='
            && $untrimmed_input_line =~ /^=[A-Za-z_]/ )
        {

            # must not be in multi-line quote
            # and must not be in an equation
            if ( !$in_quote
                && ( operator_expected( [ 'b', '=', 'b' ] ) == TERM ) )
            {
                $tokenizer_self->[_in_pod_] = 1;
                return;
            }
        }

        $input_line = $untrimmed_input_line;

        chomp $input_line;

        # Set a flag to indicate if we might be at an __END__ or __DATA__ line
        # This will be used below to avoid quoting a bare word followed by
        # a fat comma.
        my $is_END_or_DATA;

        # trim start of this line unless we are continuing a quoted line
        # do not trim end because we might end in a quote (test: deken4.pl)
        # Perl::Tidy::Formatter will delete needless trailing blanks
        unless ( $in_quote && ( $quote_type eq 'Q' ) ) {
            $input_line =~ s/^\s+//;    # trim left end

            $is_END_or_DATA = substr( $input_line, 0, 1 ) eq '_'
              && $input_line =~ /^\s*__(END|DATA)__\s*$/;
        }

        # update the copy of the line for use in error messages
        # This must be exactly what we give the pre_tokenizer
        $tokenizer_self->[_line_of_text_] = $input_line;

        # re-initialize for the main loop
        $routput_token_list     = [];    # stack of output token indexes
        $routput_token_type     = [];    # token types
        $routput_block_type     = [];    # types of code block
        $routput_container_type = [];    # paren types, such as if, elsif, ..
        $routput_type_sequence  = [];    # nesting sequential number

        $rhere_target_list = [];

        $tok             = $last_nonblank_token;
        $type            = $last_nonblank_type;
        $prototype       = $last_nonblank_prototype;
        $last_nonblank_i = -1;
        $block_type      = $last_nonblank_block_type;
        $container_type  = $last_nonblank_container_type;
        $type_sequence   = $last_nonblank_type_sequence;
        $indent_flag     = 0;
        $peeked_ahead    = 0;

        # tokenization is done in two stages..
        # stage 1 is a very simple pre-tokenization
        my $max_tokens_wanted = 0; # this signals pre_tokenize to get all tokens

        # optimize for a full-line comment
        if ( !$in_quote && substr( $input_line, 0, 1 ) eq '#' ) {
            $max_tokens_wanted = 1;    # no use tokenizing a comment

            # and check for skipped section
            if (   $rOpts_code_skipping
                && $input_line =~ /$code_skipping_pattern_begin/ )
            {
                $tokenizer_self->[_in_skipped_] = 1;
                return;
            }
        }

        # start by breaking the line into pre-tokens
        ( $rtokens, $rtoken_map, $rtoken_type ) =
          pre_tokenize( $input_line, $max_tokens_wanted );

        $max_token_index = scalar( @{$rtokens} ) - 1;
        push( @{$rtokens}, ' ', ' ', ' ' );  # extra whitespace simplifies logic
        push( @{$rtoken_map},  0,   0,   0 );     # shouldn't be referenced
        push( @{$rtoken_type}, 'b', 'b', 'b' );

        # initialize for main loop
        foreach my $ii ( 0 .. $max_token_index + 3 ) {
            $routput_token_type->[$ii]     = "";
            $routput_block_type->[$ii]     = "";
            $routput_container_type->[$ii] = "";
            $routput_type_sequence->[$ii]  = "";
            $routput_indent_flag->[$ii]    = 0;
        }
        $i     = -1;
        $i_tok = -1;

        # ------------------------------------------------------------
        # begin main tokenization loop
        # ------------------------------------------------------------

        # we are looking at each pre-token of one line and combining them
        # into tokens
        while ( ++$i <= $max_token_index ) {

            if ($in_quote) {    # continue looking for end of a quote
                $type = $quote_type;

                unless ( @{$routput_token_list} )
                {               # initialize if continuation line
                    push( @{$routput_token_list}, $i );
                    $routput_token_type->[$i] = $type;

                }

                # Removed to fix b1280.  This is not needed and was causing the
                # starting type 'qw' to be lost, leading to mis-tokenization of
                # a trailing block brace in a parenless for stmt 'for .. qw.. {'
                ##$tok = $quote_character if ($quote_character);

                # scan for the end of the quote or pattern
                (
                    $i, $in_quote, $quote_character, $quote_pos, $quote_depth,
                    $quoted_string_1, $quoted_string_2
                  )
                  = do_quote(
                    $i,               $in_quote,    $quote_character,
                    $quote_pos,       $quote_depth, $quoted_string_1,
                    $quoted_string_2, $rtokens,     $rtoken_map,
                    $max_token_index
                  );

                # all done if we didn't find it
                last if ($in_quote);

                # save pattern and replacement text for rescanning
                my $qs1 = $quoted_string_1;
                my $qs2 = $quoted_string_2;

                # re-initialize for next search
                $quote_character = '';
                $quote_pos       = 0;
                $quote_type      = 'Q';
                $quoted_string_1 = "";
                $quoted_string_2 = "";
                last if ( ++$i > $max_token_index );

                # look for any modifiers
                if ($allowed_quote_modifiers) {

                    # check for exact quote modifiers
                    if ( $rtokens->[$i] =~ /^[A-Za-z_]/ ) {
                        my $str = $rtokens->[$i];
                        my $saw_modifier_e;
                        while ( $str =~ /\G$allowed_quote_modifiers/gc ) {
                            my $pos  = pos($str);
                            my $char = substr( $str, $pos - 1, 1 );
                            $saw_modifier_e ||= ( $char eq 'e' );
                        }

                        # For an 'e' quote modifier we must scan the replacement
                        # text for here-doc targets...
                        # but if the modifier starts a new line we can skip
                        # this because either the here doc will be fully
                        # contained in the replacement text (so we can
                        # ignore it) or Perl will not find it.
                        # See test 'here2.in'.
                        if ( $saw_modifier_e && $i_tok >= 0 ) {

                            my $rht = scan_replacement_text($qs1);

                            # Change type from 'Q' to 'h' for quotes with
                            # here-doc targets so that the formatter (see sub
                            # process_line_of_CODE) will not make any line
                            # breaks after this point.
                            if ($rht) {
                                push @{$rhere_target_list}, @{$rht};
                                $type = 'h';
                                if ( $i_tok < 0 ) {
                                    my $ilast = $routput_token_list->[-1];
                                    $routput_token_type->[$ilast] = $type;
                                }
                            }
                        }

                        if ( defined( pos($str) ) ) {

                            # matched
                            if ( pos($str) == length($str) ) {
                                last if ( ++$i > $max_token_index );
                            }

                            # Looks like a joined quote modifier
                            # and keyword, maybe something like
                            # s/xxx/yyy/gefor @k=...
                            # Example is "galgen.pl".  Would have to split
                            # the word and insert a new token in the
                            # pre-token list.  This is so rare that I haven't
                            # done it.  Will just issue a warning citation.

                            # This error might also be triggered if my quote
                            # modifier characters are incomplete
                            else {
                                warning(<<EOM);

Partial match to quote modifier $allowed_quote_modifiers at word: '$str'
Please put a space between quote modifiers and trailing keywords.
EOM

                         # print "token $rtokens->[$i]\n";
                         # my $num = length($str) - pos($str);
                         # $rtokens->[$i]=substr($rtokens->[$i],pos($str),$num);
                         # print "continuing with new token $rtokens->[$i]\n";

                                # skipping past this token does least damage
                                last if ( ++$i > $max_token_index );
                            }
                        }
                        else {

                            # example file: rokicki4.pl
                            # This error might also be triggered if my quote
                            # modifier characters are incomplete
                            write_logfile_entry(
"Note: found word $str at quote modifier location\n"
                            );
                        }
                    }

                    # re-initialize
                    $allowed_quote_modifiers = "";
                }
            }

            unless ( $type eq 'b' || $tok eq 'CORE::' ) {

                # try to catch some common errors
                if ( ( $type eq 'n' ) && ( $tok ne '0' ) ) {

                    if ( $last_nonblank_token eq 'eq' ) {
                        complain("Should 'eq' be '==' here ?\n");
                    }
                    elsif ( $last_nonblank_token eq 'ne' ) {
                        complain("Should 'ne' be '!=' here ?\n");
                    }
                }

                # fix c090, only rotate vars if a new token will be stored
                if ( $i_tok >= 0 ) {
                    $last_last_nonblank_token      = $last_nonblank_token;
                    $last_last_nonblank_type       = $last_nonblank_type;
                    $last_last_nonblank_block_type = $last_nonblank_block_type;
                    $last_last_nonblank_container_type =
                      $last_nonblank_container_type;
                    $last_last_nonblank_type_sequence =
                      $last_nonblank_type_sequence;
                    $last_nonblank_token          = $tok;
                    $last_nonblank_type           = $type;
                    $last_nonblank_prototype      = $prototype;
                    $last_nonblank_block_type     = $block_type;
                    $last_nonblank_container_type = $container_type;
                    $last_nonblank_type_sequence  = $type_sequence;
                    $last_nonblank_i              = $i_tok;
                }

                # Patch for c030: Fix things in case a '->' got separated from
                # the subsequent identifier by a side comment.  We need the
                # last_nonblank_token to have a leading -> to avoid triggering
                # an operator expected error message at the next '('. See also
                # fix for git #63.
                if ( $last_last_nonblank_token eq '->' ) {
                    if (   $last_nonblank_type eq 'w'
                        || $last_nonblank_type eq 'i'
                        && substr( $last_nonblank_token, 0, 1 ) eq '$' )
                    {
                        $last_nonblank_token = '->' . $last_nonblank_token;
                        $last_nonblank_type  = 'i';
                    }
                }
            }

            # store previous token type
            if ( $i_tok >= 0 ) {
                $routput_token_type->[$i_tok]     = $type;
                $routput_block_type->[$i_tok]     = $block_type;
                $routput_container_type->[$i_tok] = $container_type;
                $routput_type_sequence->[$i_tok]  = $type_sequence;
                $routput_indent_flag->[$i_tok]    = $indent_flag;
            }
            my $pre_tok  = $rtokens->[$i];        # get the next pre-token
            my $pre_type = $rtoken_type->[$i];    # and type
            $tok        = $pre_tok;
            $type       = $pre_type;              # to be modified as necessary
            $block_type = "";    # blank for all tokens except code block braces
            $container_type = "";    # blank for all tokens except some parens
            $type_sequence  = "";    # blank for all tokens except ?/:
            $indent_flag    = 0;
            $prototype = "";    # blank for all tokens except user defined subs
            $i_tok     = $i;

            # this pre-token will start an output token
            push( @{$routput_token_list}, $i_tok );

            # continue gathering identifier if necessary
            # but do not start on blanks and comments
            if ( $id_scan_state && $pre_type ne 'b' && $pre_type ne '#' ) {

                if ( $is_sub{$id_scan_state} || $is_package{$id_scan_state} ) {
                    scan_id();
                }
                else {
                    scan_identifier();
                }

                if ($id_scan_state) {

                    # Still scanning ...
                    # Check for side comment between sub and prototype (c061)

                    # done if nothing left to scan on this line
                    last if ( $i > $max_token_index );

                    my ( $next_nonblank_token, $i_next ) =
                      find_next_nonblank_token_on_this_line( $i, $rtokens,
                        $max_token_index );

                    # done if it was just some trailing space
                    last if ( $i_next > $max_token_index );

                    # something remains on the line ... must be a side comment
                    next;
                }

                next if ( ( $i > 0 ) || $type );

                # didn't find any token; start over
                $type = $pre_type;
                $tok  = $pre_tok;
            }

            # handle whitespace tokens..
            next if ( $type eq 'b' );
            my $prev_tok  = $i > 0 ? $rtokens->[ $i - 1 ]     : ' ';
            my $prev_type = $i > 0 ? $rtoken_type->[ $i - 1 ] : 'b';

            # Build larger tokens where possible, since we are not in a quote.
            #
            # First try to assemble digraphs.  The following tokens are
            # excluded and handled specially:
            # '/=' is excluded because the / might start a pattern.
            # 'x=' is excluded since it might be $x=, with $ on previous line
            # '**' and *= might be typeglobs of punctuation variables
            # I have allowed tokens starting with <, such as <=,
            # because I don't think these could be valid angle operators.
            # test file: storrs4.pl
            my $test_tok   = $tok . $rtokens->[ $i + 1 ];
            my $combine_ok = $is_digraph{$test_tok};

            # check for special cases which cannot be combined
            if ($combine_ok) {

                # '//' must be defined_or operator if an operator is expected.
                # TODO: Code for other ambiguous digraphs (/=, x=, **, *=)
                # could be migrated here for clarity

              # Patch for RT#102371, misparsing a // in the following snippet:
              #     state $b //= ccc();
              # The solution is to always accept the digraph (or trigraph) after
              # token type 'Z' (possible file handle).  The reason is that
              # sub operator_expected gives TERM expected here, which is
              # wrong in this case.
                if ( $test_tok eq '//' && $last_nonblank_type ne 'Z' ) {
                    my $next_type = $rtokens->[ $i + 1 ];
                    my $expecting =
                      operator_expected( [ $prev_type, $tok, $next_type ] );

                    # Patched for RT#101547, was 'unless ($expecting==OPERATOR)'
                    $combine_ok = 0 if ( $expecting == TERM );
                }

                # Patch for RT #114359: Missparsing of "print $x ** 0.5;
                # Accept the digraphs '**' only after type 'Z'
                # Otherwise postpone the decision.
                if ( $test_tok eq '**' ) {
                    if ( $last_nonblank_type ne 'Z' ) { $combine_ok = 0 }
                }
            }

            if (
                $combine_ok

                && ( $test_tok ne '/=' )    # might be pattern
                && ( $test_tok ne 'x=' )    # might be $x
                && ( $test_tok ne '*=' )    # typeglob?

                # Moved above as part of fix for
                # RT #114359: Missparsing of "print $x ** 0.5;
                # && ( $test_tok ne '**' )    # typeglob?
              )
            {
                $tok = $test_tok;
                $i++;

                # Now try to assemble trigraphs.  Note that all possible
                # perl trigraphs can be constructed by appending a character
                # to a digraph.
                $test_tok = $tok . $rtokens->[ $i + 1 ];

                if ( $is_trigraph{$test_tok} ) {
                    $tok = $test_tok;
                    $i++;
                }

                # The only current tetragraph is the double diamond operator
                # and its first three characters are not a trigraph, so
                # we do can do a special test for it
                elsif ( $test_tok eq '<<>' ) {
                    $test_tok .= $rtokens->[ $i + 2 ];
                    if ( $is_tetragraph{$test_tok} ) {
                        $tok = $test_tok;
                        $i += 2;
                    }
                }
            }

            $type      = $tok;
            $next_tok  = $rtokens->[ $i + 1 ];
            $next_type = $rtoken_type->[ $i + 1 ];

            DEBUG_TOKENIZE && do {
                local $" = ')(';
                my @debug_list = (
                    $last_nonblank_token,      $tok,
                    $next_tok,                 $brace_depth,
                    $brace_type[$brace_depth], $paren_depth,
                    $paren_type[$paren_depth]
                );
                print STDOUT "TOKENIZE:(@debug_list)\n";
            };

            # Turn off attribute list on first non-blank, non-bareword.
            # Added '#' to fix c038.
            if ( $pre_type ne 'w' && $pre_type ne '#' ) {
                $in_attribute_list = 0;
            }

            ###############################################################
            # We have the next token, $tok.
            # Now we have to examine this token and decide what it is
            # and define its $type
            #
            # section 1: bare words
            ###############################################################

            if ( $pre_type eq 'w' ) {
                $expecting =
                  operator_expected( [ $prev_type, $tok, $next_type ] );

                # Patch for c043, part 3: A bareword after '->' expects a TERM
                # FIXME: It would be cleaner to give method calls a new type 'M'
                # and update sub operator_expected to handle this.
                if ( $last_nonblank_type eq '->' ) {
                    $expecting = TERM;
                }

                my ( $next_nonblank_token, $i_next ) =
                  find_next_nonblank_token( $i, $rtokens, $max_token_index );

                # ATTRS: handle sub and variable attributes
                if ($in_attribute_list) {

                    # treat bare word followed by open paren like qw(
                    if ( $next_nonblank_token eq '(' ) {

                        # For something like:
                        #     : prototype($$)
                        # we should let do_scan_sub see it so that it can see
                        # the prototype.  All other attributes get parsed as a
                        # quoted string.
                        if ( $tok eq 'prototype' ) {
                            $id_scan_state = 'prototype';

                            # start just after the word 'prototype'
                            my $i_beg = $i + 1;
                            ( $i, $tok, $type, $id_scan_state ) = do_scan_sub(
                                {
                                    input_line      => $input_line,
                                    i               => $i,
                                    i_beg           => $i_beg,
                                    tok             => $tok,
                                    type            => $type,
                                    rtokens         => $rtokens,
                                    rtoken_map      => $rtoken_map,
                                    id_scan_state   => $id_scan_state,
                                    max_token_index => $max_token_index
                                }
                            );

                   # If successful, mark as type 'q' to be consistent with other
                   # attributes.  Note that type 'w' would also work.
                            if ( $i > $i_beg ) {
                                $type = 'q';
                                next;
                            }

                            # If not successful, continue and parse as a quote.
                        }

                        # All other attribute lists must be parsed as quotes
                        # (see 'signatures.t' for good examples)
                        $in_quote                = $quote_items{'q'};
                        $allowed_quote_modifiers = $quote_modifiers{'q'};
                        $type                    = 'q';
                        $quote_type              = 'q';
                        next;
                    }

                    # handle bareword not followed by open paren
                    else {
                        $type = 'w';
                        next;
                    }
                }

                # quote a word followed by => operator
                # unless the word __END__ or __DATA__ and the only word on
                # the line.
                if ( !$is_END_or_DATA && $next_nonblank_token eq '=' ) {

                    if ( $rtokens->[ $i_next + 1 ] eq '>' ) {
                        if ( $is_constant{$current_package}{$tok} ) {
                            $type = 'C';
                        }
                        elsif ( $is_user_function{$current_package}{$tok} ) {
                            $type = 'U';
                            $prototype =
                              $user_function_prototype{$current_package}{$tok};
                        }
                        elsif ( $tok =~ /^v\d+$/ ) {
                            $type = 'v';
                            report_v_string($tok);
                        }
                        else {

                           # Bareword followed by a fat comma ... see 'git18.in'
                           # If tok is something like 'x17' then it could
                           # actually be operator x followed by number 17.
                           # For example, here:
                           #     123x17 => [ 792, 1224 ],
                           # (a key of 123 repeated 17 times, perhaps not
                           # what was intended). We will mark x17 as type
                           # 'n' and it will be split. If the previous token
                           # was also a bareword then it is not very clear is
                           # going on.  In this case we will not be sure that
                           # an operator is expected, so we just mark it as a
                           # bareword.  Perl is a little murky in what it does
                           # with stuff like this, and its behavior can change
                           # over time.  Something like
                           #    a x18 => [792, 1224], will compile as
                           # a key with 18 a's.  But something like
                           #    push @array, a x18;
                           # is a syntax error.
                            if (
                                   $expecting == OPERATOR
                                && substr( $tok, 0, 1 ) eq 'x'
                                && ( length($tok) == 1
                                    || substr( $tok, 1, 1 ) =~ /^\d/ )
                              )
                            {
                                $type = 'n';
                                if ( split_pretoken(1) ) {
                                    $type = 'x';
                                    $tok  = 'x';
                                }
                            }
                            else {

                                # git #18
                                $type = 'w';
                                error_if_expecting_OPERATOR();
                            }
                        }

                        next;
                    }
                }

     # quote a bare word within braces..like xxx->{s}; note that we
     # must be sure this is not a structural brace, to avoid
     # mistaking {s} in the following for a quoted bare word:
     #     for(@[){s}bla}BLA}
     # Also treat q in something like var{-q} as a bare word, not qoute operator
                if (
                    $next_nonblank_token eq '}'
                    && (
                        $last_nonblank_type eq 'L'
                        || (   $last_nonblank_type eq 'm'
                            && $last_last_nonblank_type eq 'L' )
                    )
                  )
                {
                    $type = 'w';
                    next;
                }

                # Scan a bare word following a -> as an identifir; it could
                # have a long package name.  Fixes c037, c041.
                if ( $last_nonblank_token eq '->' ) {
                    scan_bare_identifier();

                    # Patch for c043, part 4; use type 'w' after a '->'.
                    # This is just a safety check on sub scan_bare_identifier,
                    # which should get this case correct.
                    $type = 'w';
                    next;
                }

                # a bare word immediately followed by :: is not a keyword;
                # use $tok_kw when testing for keywords to avoid a mistake
                my $tok_kw = $tok;
                if (   $rtokens->[ $i + 1 ] eq ':'
                    && $rtokens->[ $i + 2 ] eq ':' )
                {
                    $tok_kw .= '::';
                }

                # Decide if 'sub :' can be the start of a sub attribute list.
                # We will decide based on if the colon is followed by a
                # bareword which is not a keyword.
                # Changed inext+1 to inext to fixed case b1190.
                my $sub_attribute_ok_here;
                if (   $is_sub{$tok_kw}
                    && $expecting != OPERATOR
                    && $next_nonblank_token eq ':' )
                {
                    my ( $nn_nonblank_token, $i_nn ) =
                      find_next_nonblank_token( $i_next,
                        $rtokens, $max_token_index );
                    $sub_attribute_ok_here =
                         $nn_nonblank_token =~ /^\w/
                      && $nn_nonblank_token !~ /^\d/
                      && !$is_keyword{$nn_nonblank_token};
                }

                # handle operator x (now we know it isn't $x=)
                if (
                       $expecting == OPERATOR
                    && substr( $tok, 0, 1 ) eq 'x'
                    && ( length($tok) == 1
                        || substr( $tok, 1, 1 ) =~ /^\d/ )
                  )
                {

                    if ( $tok eq 'x' ) {
                        if ( $rtokens->[ $i + 1 ] eq '=' ) {    # x=
                            $tok  = 'x=';
                            $type = $tok;
                            $i++;
                        }
                        else {
                            $type = 'x';
                        }
                    }
                    else {

                        # Split a pretoken like 'x10' into 'x' and '10'.
                        # Note: In previous versions of perltidy it was marked
                        # as a number, $type = 'n', and fixed downstream by the
                        # Formatter.
                        $type = 'n';
                        if ( split_pretoken(1) ) {
                            $type = 'x';
                            $tok  = 'x';
                        }
                    }
                }
                elsif ( $tok_kw eq 'CORE::' ) {
                    $type = $tok = $tok_kw;
                    $i += 2;
                }
                elsif ( ( $tok eq 'strict' )
                    and ( $last_nonblank_token eq 'use' ) )
                {
                    $tokenizer_self->[_saw_use_strict_] = 1;
                    scan_bare_identifier();
                }

                elsif ( ( $tok eq 'warnings' )
                    and ( $last_nonblank_token eq 'use' ) )
                {
                    $tokenizer_self->[_saw_perl_dash_w_] = 1;

                    # scan as identifier, so that we pick up something like:
                    # use warnings::register
                    scan_bare_identifier();
                }

                elsif (
                       $tok eq 'AutoLoader'
                    && $tokenizer_self->[_look_for_autoloader_]
                    && (
                        $last_nonblank_token eq 'use'

                        # these regexes are from AutoSplit.pm, which we want
                        # to mimic
                        || $input_line =~ /^\s*(use|require)\s+AutoLoader\b/
                        || $input_line =~ /\bISA\s*=.*\bAutoLoader\b/
                    )
                  )
                {
                    write_logfile_entry("AutoLoader seen, -nlal deactivates\n");
                    $tokenizer_self->[_saw_autoloader_]      = 1;
                    $tokenizer_self->[_look_for_autoloader_] = 0;
                    scan_bare_identifier();
                }

                elsif (
                       $tok eq 'SelfLoader'
                    && $tokenizer_self->[_look_for_selfloader_]
                    && (   $last_nonblank_token eq 'use'
                        || $input_line =~ /^\s*(use|require)\s+SelfLoader\b/
                        || $input_line =~ /\bISA\s*=.*\bSelfLoader\b/ )
                  )
                {
                    write_logfile_entry("SelfLoader seen, -nlsl deactivates\n");
                    $tokenizer_self->[_saw_selfloader_]      = 1;
                    $tokenizer_self->[_look_for_selfloader_] = 0;
                    scan_bare_identifier();
                }

                elsif ( ( $tok eq 'constant' )
                    and ( $last_nonblank_token eq 'use' ) )
                {
                    scan_bare_identifier();
                    my ( $next_nonblank_token, $i_next ) =
                      find_next_nonblank_token( $i, $rtokens,
                        $max_token_index );

                    if ($next_nonblank_token) {

                        if ( $is_keyword{$next_nonblank_token} ) {

                            # Assume qw is used as a quote and okay, as in:
                            #  use constant qw{ DEBUG 0 };
                            # Not worth trying to parse for just a warning

                            # NOTE: This warning is deactivated because recent
                            # versions of perl do not complain here, but
                            # the coding is retained for reference.
                            if ( 0 && $next_nonblank_token ne 'qw' ) {
                                warning(
"Attempting to define constant '$next_nonblank_token' which is a perl keyword\n"
                                );
                            }
                        }

                        else {
                            $is_constant{$current_package}{$next_nonblank_token}
                              = 1;
                        }
                    }
                }

                # various quote operators
                elsif ( $is_q_qq_qw_qx_qr_s_y_tr_m{$tok} ) {
##NICOL PATCH
                    if ( $expecting == OPERATOR ) {

                        # Be careful not to call an error for a qw quote
                        # where a parenthesized list is allowed.  For example,
                        # it could also be a for/foreach construct such as
                        #
                        #    foreach my $key qw\Uno Due Tres Quadro\ {
                        #        print "Set $key\n";
                        #    }
                        #

                        # Or it could be a function call.
                        # NOTE: Braces in something like &{ xxx } are not
                        # marked as a block, we might have a method call.
                        # &method(...), $method->(..), &{method}(...),
                        # $ref[2](list) is ok & short for $ref[2]->(list)
                        #
                        # See notes in 'sub code_block_type' and
                        # 'sub is_non_structural_brace'

                        unless (
                            $tok eq 'qw'
                            && (   $last_nonblank_token =~ /^([\]\}\&]|\-\>)/
                                || $is_for_foreach{$want_paren} )
                          )
                        {
                            error_if_expecting_OPERATOR();
                        }
                    }
                    $in_quote                = $quote_items{$tok};
                    $allowed_quote_modifiers = $quote_modifiers{$tok};

                   # All quote types are 'Q' except possibly qw quotes.
                   # qw quotes are special in that they may generally be trimmed
                   # of leading and trailing whitespace.  So they are given a
                   # separate type, 'q', unless requested otherwise.
                    $type =
                      ( $tok eq 'qw' && $tokenizer_self->[_trim_qw_] )
                      ? 'q'
                      : 'Q';
                    $quote_type = $type;
                }

                # check for a statement label
                elsif (
                       ( $next_nonblank_token eq ':' )
                    && ( $rtokens->[ $i_next + 1 ] ne ':' )
                    && ( $i_next <= $max_token_index )   # colon on same line
                    && !$sub_attribute_ok_here           # like 'sub : lvalue' ?
                    && label_ok()
                  )
                {
                    if ( $tok !~ /[A-Z]/ ) {
                        push @{ $tokenizer_self->[_rlower_case_labels_at_] },
                          $input_line_number;
                    }
                    $type = 'J';
                    $tok .= ':';
                    $i = $i_next;
                    next;
                }

                #      'sub' or alias
                elsif ( $is_sub{$tok_kw} ) {
                    error_if_expecting_OPERATOR()
                      if ( $expecting == OPERATOR );
                    initialize_subname();
                    scan_id();
                }

                #      'package'
                elsif ( $is_package{$tok_kw} ) {
                    error_if_expecting_OPERATOR()
                      if ( $expecting == OPERATOR );
                    scan_id();
                }

                # Fix for c035: split 'format' from 'is_format_END_DATA' to be
                # more restrictive. Require a new statement to be ok here.
                elsif ( $tok_kw eq 'format' && new_statement_ok() ) {
                    $type = ';';    # make tokenizer look for TERM next
                    $tokenizer_self->[_in_format_] = 1;
                    last;
                }

                # Note on token types for format, __DATA__, __END__:
                # It simplifies things to give these type ';', so that when we
                # start rescanning we will be expecting a token of type TERM.
                # We will switch to type 'k' before outputting the tokens.
                elsif ( $is_END_DATA{$tok_kw} ) {
                    $type = ';';    # make tokenizer look for TERM next

                    # Remember that we are in one of these three sections
                    $tokenizer_self->[ $is_END_DATA{$tok_kw} ] = 1;
                    last;
                }

                elsif ( $is_keyword{$tok_kw} ) {
                    $type = 'k';

                    # Since for and foreach may not be followed immediately
                    # by an opening paren, we have to remember which keyword
                    # is associated with the next '('
                    if ( $is_for_foreach{$tok} ) {
                        if ( new_statement_ok() ) {
                            $want_paren = $tok;
                        }
                    }

                    # recognize 'use' statements, which are special
                    elsif ( $is_use_require{$tok} ) {
                        $statement_type = $tok;
                        error_if_expecting_OPERATOR()
                          if ( $expecting == OPERATOR );
                    }

                    # remember my and our to check for trailing ": shared"
                    elsif ( $is_my_our_state{$tok} ) {
                        $statement_type = $tok;
                    }

                    # Check for misplaced 'elsif' and 'else', but allow isolated
                    # else or elsif blocks to be formatted.  This is indicated
                    # by a last noblank token of ';'
                    elsif ( $tok eq 'elsif' ) {
                        if (   $last_nonblank_token ne ';'
                            && $last_nonblank_block_type !~
                            /^(if|elsif|unless)$/ )
                        {
                            warning(
"expecting '$tok' to follow one of 'if|elsif|unless'\n"
                            );
                        }
                    }
                    elsif ( $tok eq 'else' ) {

                        # patched for SWITCH/CASE
                        if (
                               $last_nonblank_token ne ';'
                            && $last_nonblank_block_type !~
                            /^(if|elsif|unless|case|when)$/

                            # patch to avoid an unwanted error message for
                            # the case of a parenless 'case' (RT 105484):
                            # switch ( 1 ) { case x { 2 } else { } }
                            && $statement_type !~
                            /^(if|elsif|unless|case|when)$/
                          )
                        {
                            warning(
"expecting '$tok' to follow one of 'if|elsif|unless|case|when'\n"
                            );
                        }
                    }
                    elsif ( $tok eq 'continue' ) {
                        if (   $last_nonblank_token ne ';'
                            && $last_nonblank_block_type !~
                            /(^(\{|\}|;|while|until|for|foreach)|:$)/ )
                        {

                            # note: ';' '{' and '}' in list above
                            # because continues can follow bare blocks;
                            # ':' is labeled block
                            #
                            ############################################
                            # NOTE: This check has been deactivated because
                            # continue has an alternative usage for given/when
                            # blocks in perl 5.10
                            ## warning("'$tok' should follow a block\n");
                            ############################################
                        }
                    }

                    # patch for SWITCH/CASE if 'case' and 'when are
                    # treated as keywords.  Also 'default' for Switch::Plain
                    elsif ($tok eq 'when'
                        || $tok eq 'case'
                        || $tok eq 'default' )
                    {
                        $statement_type = $tok;    # next '{' is block
                    }

                    #
                    # indent trailing if/unless/while/until
                    # outdenting will be handled by later indentation loop
## DEACTIVATED: unfortunately this can cause some unwanted indentation like:
##$opt_o = 1
##  if !(
##             $opt_b
##          || $opt_c
##          || $opt_d
##          || $opt_f
##          || $opt_i
##          || $opt_l
##          || $opt_o
##          || $opt_x
##  );
##                    if (   $tok =~ /^(if|unless|while|until)$/
##                        && $next_nonblank_token ne '(' )
##                    {
##                        $indent_flag = 1;
##                    }
                }

                # check for inline label following
                #         /^(redo|last|next|goto)$/
                elsif (( $last_nonblank_type eq 'k' )
                    && ( $is_redo_last_next_goto{$last_nonblank_token} ) )
                {
                    $type = 'j';
                    next;
                }

                # something else --
                else {

                    scan_bare_identifier();

                    if (   $statement_type eq 'use'
                        && $last_nonblank_token eq 'use' )
                    {
                        $saw_use_module{$current_package}->{$tok} = 1;
                    }

                    if ( $type eq 'w' ) {

                        if ( $expecting == OPERATOR ) {

                            # Patch to avoid error message for RPerl overloaded
                            # operator functions: use overload
                            #    '+' => \&sse_add,
                            #    '-' => \&sse_sub,
                            #    '*' => \&sse_mul,
                            #    '/' => \&sse_div;
                            # FIXME: this should eventually be generalized
                            if (   $saw_use_module{$current_package}->{'RPerl'}
                                && $tok =~ /^sse_(mul|div|add|sub)$/ )
                            {

                            }

                            # Fix part 1 for git #63 in which a comment falls
                            # between an -> and the following word.  An
                            # alternate fix would be to change operator_expected
                            # to return an UNKNOWN for this type.
                            elsif ( $last_nonblank_type eq '->' ) {

                            }

                            # don't complain about possible indirect object
                            # notation.
                            # For example:
                            #   package main;
                            #   sub new($) { ... }
                            #   $b = new A::;  # calls A::new
                            #   $c = new A;    # same thing but suspicious
                            # This will call A::new but we have a 'new' in
                            # main:: which looks like a constant.
                            #
                            elsif ( $last_nonblank_type eq 'C' ) {
                                if ( $tok !~ /::$/ ) {
                                    complain(<<EOM);
Expecting operator after '$last_nonblank_token' but found bare word '$tok'
       Maybe indirectet object notation?
EOM
                                }
                            }
                            else {
                                error_if_expecting_OPERATOR("bareword");
                            }
                        }

                        # mark bare words immediately followed by a paren as
                        # functions
                        $next_tok = $rtokens->[ $i + 1 ];
                        if ( $next_tok eq '(' ) {

                            # Fix part 2 for git #63.  Leave type as 'w' to keep
                            # the type the same as if the -> were not separated
                            $type = 'U' unless ( $last_nonblank_type eq '->' );
                        }

                        # underscore after file test operator is file handle
                        if ( $tok eq '_' && $last_nonblank_type eq 'F' ) {
                            $type = 'Z';
                        }

                        # patch for SWITCH/CASE if 'case' and 'when are
                        # not treated as keywords:
                        if (
                            (
                                   $tok eq 'case'
                                && $brace_type[$brace_depth] eq 'switch'
                            )
                            || (   $tok eq 'when'
                                && $brace_type[$brace_depth] eq 'given' )
                          )
                        {
                            $statement_type = $tok;    # next '{' is block
                            $type           = 'k'; # for keyword syntax coloring
                        }

                        # patch for SWITCH/CASE if switch and given not keywords
                        # Switch is not a perl 5 keyword, but we will gamble
                        # and mark switch followed by paren as a keyword.  This
                        # is only necessary to get html syntax coloring nice,
                        # and does not commit this as being a switch/case.
                        if ( $next_nonblank_token eq '('
                            && ( $tok eq 'switch' || $tok eq 'given' ) )
                        {
                            $type = 'k';    # for keyword syntax coloring
                        }
                    }
                }
            }

            ###############################################################
            # section 2: strings of digits
            ###############################################################
            elsif ( $pre_type eq 'd' ) {
                $expecting =
                  operator_expected( [ $prev_type, $tok, $next_type ] );
                error_if_expecting_OPERATOR("Number")
                  if ( $expecting == OPERATOR );

                my $number = scan_number_fast();
                if ( !defined($number) ) {

                    # shouldn't happen - we should always get a number
                    if (DEVEL_MODE) {
                        Fault(<<EOM);
non-number beginning with digit--program bug
EOM
                    }
                    warning(
"Unexpected error condition: non-number beginning with digit\n"
                    );
                    report_definite_bug();
                }
            }

            ###############################################################
            # section 3: all other tokens
            ###############################################################

            else {
                last if ( $tok eq '#' );
                my $code = $tokenization_code->{$tok};
                if ($code) {
                    $expecting =
                      operator_expected( [ $prev_type, $tok, $next_type ] );
                    $code->();
                    redo if $in_quote;
                }
            }
        }

        # -----------------------------
        # end of main tokenization loop
        # -----------------------------

        if ( $i_tok >= 0 ) {
            $routput_token_type->[$i_tok]     = $type;
            $routput_block_type->[$i_tok]     = $block_type;
            $routput_container_type->[$i_tok] = $container_type;
            $routput_type_sequence->[$i_tok]  = $type_sequence;
            $routput_indent_flag->[$i_tok]    = $indent_flag;
        }

        unless ( ( $type eq 'b' ) || ( $type eq '#' ) ) {
            $last_last_nonblank_token          = $last_nonblank_token;
            $last_last_nonblank_type           = $last_nonblank_type;
            $last_last_nonblank_block_type     = $last_nonblank_block_type;
            $last_last_nonblank_container_type = $last_nonblank_container_type;
            $last_last_nonblank_type_sequence  = $last_nonblank_type_sequence;
            $last_nonblank_token               = $tok;
            $last_nonblank_type                = $type;
            $last_nonblank_block_type          = $block_type;
            $last_nonblank_container_type      = $container_type;
            $last_nonblank_type_sequence       = $type_sequence;
            $last_nonblank_prototype           = $prototype;
        }

        # reset indentation level if necessary at a sub or package
        # in an attempt to recover from a nesting error
        if ( $level_in_tokenizer < 0 ) {
            if ( $input_line =~ /^\s*(sub|package)\s+(\w+)/ ) {
                reset_indentation_level(0);
                brace_warning("resetting level to 0 at $1 $2\n");
            }
        }

        # all done tokenizing this line ...
        # now prepare the final list of tokens and types

        my @token_type     = ();   # stack of output token types
        my @block_type     = ();   # stack of output code block types
        my @container_type = ();   # stack of output code container types
        my @type_sequence  = ();   # stack of output type sequence numbers
        my @tokens         = ();   # output tokens
        my @levels         = ();   # structural brace levels of output tokens
        my @slevels        = ();   # secondary nesting levels of output tokens
        my @nesting_tokens = ();   # string of tokens leading to this depth
        my @nesting_types  = ();   # string of token types leading to this depth
        my @nesting_blocks = ();   # string of block types leading to this depth
        my @nesting_lists  = ();   # string of list types leading to this depth
        my @ci_string = ();  # string needed to compute continuation indentation
        my @container_environment = ();    # BLOCK or LIST
        my $container_environment = '';
        my $im                    = -1;    # previous $i value
        my $num;

        # Count the number of '1's in the string (previously sub ones_count)
        my $ci_string_sum = ( my $str = $ci_string_in_tokenizer ) =~ tr/1/0/;

# Computing Token Indentation
#
#     The final section of the tokenizer forms tokens and also computes
#     parameters needed to find indentation.  It is much easier to do it
#     in the tokenizer than elsewhere.  Here is a brief description of how
#     indentation is computed.  Perl::Tidy computes indentation as the sum
#     of 2 terms:
#
#     (1) structural indentation, such as if/else/elsif blocks
#     (2) continuation indentation, such as long parameter call lists.
#
#     These are occasionally called primary and secondary indentation.
#
#     Structural indentation is introduced by tokens of type '{', although
#     the actual tokens might be '{', '(', or '['.  Structural indentation
#     is of two types: BLOCK and non-BLOCK.  Default structural indentation
#     is 4 characters if the standard indentation scheme is used.
#
#     Continuation indentation is introduced whenever a line at BLOCK level
#     is broken before its termination.  Default continuation indentation
#     is 2 characters in the standard indentation scheme.
#
#     Both types of indentation may be nested arbitrarily deep and
#     interlaced.  The distinction between the two is somewhat arbitrary.
#
#     For each token, we will define two variables which would apply if
#     the current statement were broken just before that token, so that
#     that token started a new line:
#
#     $level = the structural indentation level,
#     $ci_level = the continuation indentation level
#
#     The total indentation will be $level * (4 spaces) + $ci_level * (2 spaces),
#     assuming defaults.  However, in some special cases it is customary
#     to modify $ci_level from this strict value.
#
#     The total structural indentation is easy to compute by adding and
#     subtracting 1 from a saved value as types '{' and '}' are seen.  The
#     running value of this variable is $level_in_tokenizer.
#
#     The total continuation is much more difficult to compute, and requires
#     several variables.  These variables are:
#
#     $ci_string_in_tokenizer = a string of 1's and 0's indicating, for
#       each indentation level, if there are intervening open secondary
#       structures just prior to that level.
#     $continuation_string_in_tokenizer = a string of 1's and 0's indicating
#       if the last token at that level is "continued", meaning that it
#       is not the first token of an expression.
#     $nesting_block_string = a string of 1's and 0's indicating, for each
#       indentation level, if the level is of type BLOCK or not.
#     $nesting_block_flag = the most recent 1 or 0 of $nesting_block_string
#     $nesting_list_string = a string of 1's and 0's indicating, for each
#       indentation level, if it is appropriate for list formatting.
#       If so, continuation indentation is used to indent long list items.
#     $nesting_list_flag = the most recent 1 or 0 of $nesting_list_string
#     @{$rslevel_stack} = a stack of total nesting depths at each
#       structural indentation level, where "total nesting depth" means
#       the nesting depth that would occur if every nesting token -- '{', '[',
#       and '(' -- , regardless of context, is used to compute a nesting
#       depth.

        #my $nesting_block_flag = ($nesting_block_string =~ /1$/);
        #my $nesting_list_flag = ($nesting_list_string =~ /1$/);

        my ( $ci_string_i, $level_i, $nesting_block_string_i,
            $nesting_list_string_i, $nesting_token_string_i,
            $nesting_type_string_i, );

        foreach my $i ( @{$routput_token_list} )
        {    # scan the list of pre-tokens indexes

            # self-checking for valid token types
            my $type                    = $routput_token_type->[$i];
            my $forced_indentation_flag = $routput_indent_flag->[$i];

            # See if we should undo the $forced_indentation_flag.
            # Forced indentation after 'if', 'unless', 'while' and 'until'
            # expressions without trailing parens is optional and doesn't
            # always look good.  It is usually okay for a trailing logical
            # expression, but if the expression is a function call, code block,
            # or some kind of list it puts in an unwanted extra indentation
            # level which is hard to remove.
            #
            # Example where extra indentation looks ok:
            # return 1
            #   if $det_a < 0 and $det_b > 0
            #       or $det_a > 0 and $det_b < 0;
            #
            # Example where extra indentation is not needed because
            # the eval brace also provides indentation:
            # print "not " if defined eval {
            #     reduce { die if $b > 2; $a + $b } 0, 1, 2, 3, 4;
            # };
            #
            # The following rule works fairly well:
            #   Undo the flag if the end of this line, or start of the next
            #   line, is an opening container token or a comma.
            # This almost always works, but if not after another pass it will
            # be stable.
            if ( $forced_indentation_flag && $type eq 'k' ) {
                my $ixlast  = -1;
                my $ilast   = $routput_token_list->[$ixlast];
                my $toklast = $routput_token_type->[$ilast];
                if ( $toklast eq '#' ) {
                    $ixlast--;
                    $ilast   = $routput_token_list->[$ixlast];
                    $toklast = $routput_token_type->[$ilast];
                }
                if ( $toklast eq 'b' ) {
                    $ixlast--;
                    $ilast   = $routput_token_list->[$ixlast];
                    $toklast = $routput_token_type->[$ilast];
                }
                if ( $toklast =~ /^[\{,]$/ ) {
                    $forced_indentation_flag = 0;
                }
                else {
                    ( $toklast, my $i_next ) =
                      find_next_nonblank_token( $max_token_index, $rtokens,
                        $max_token_index );
                    if ( $toklast =~ /^[\{,]$/ ) {
                        $forced_indentation_flag = 0;
                    }
                }
            }

            # if we are already in an indented if, see if we should outdent
            if ($indented_if_level) {

                # don't try to nest trailing if's - shouldn't happen
                if ( $type eq 'k' ) {
                    $forced_indentation_flag = 0;
                }

                # check for the normal case - outdenting at next ';'
                elsif ( $type eq ';' ) {
                    if ( $level_in_tokenizer == $indented_if_level ) {
                        $forced_indentation_flag = -1;
                        $indented_if_level       = 0;
                    }
                }

                # handle case of missing semicolon
                elsif ( $type eq '}' ) {
                    if ( $level_in_tokenizer == $indented_if_level ) {
                        $indented_if_level = 0;

                        # TBD: This could be a subroutine call
                        $level_in_tokenizer--;
                        if ( @{$rslevel_stack} > 1 ) {
                            pop( @{$rslevel_stack} );
                        }
                        if ( length($nesting_block_string) > 1 )
                        {    # true for valid script
                            chop $nesting_block_string;
                            chop $nesting_list_string;
                        }

                    }
                }
            }

            my $tok = $rtokens->[$i];  # the token, but ONLY if same as pretoken
            $level_i = $level_in_tokenizer;

            # This can happen by running perltidy on non-scripts
            # although it could also be bug introduced by programming change.
            # Perl silently accepts a 032 (^Z) and takes it as the end
            if ( !$is_valid_token_type{$type} ) {
                my $val = ord($type);
                warning(
                    "unexpected character decimal $val ($type) in script\n");
                $tokenizer_self->[_in_error_] = 1;
            }

            # ----------------------------------------------------------------
            # TOKEN TYPE PATCHES
            #  output __END__, __DATA__, and format as type 'k' instead of ';'
            # to make html colors correct, etc.
            my $fix_type = $type;
            if ( $type eq ';' && $tok =~ /\w/ ) { $fix_type = 'k' }

            # output anonymous 'sub' as keyword
            if ( $type eq 't' && $is_sub{$tok} ) { $fix_type = 'k' }

            # -----------------------------------------------------------------

            $nesting_token_string_i = $nesting_token_string;
            $nesting_type_string_i  = $nesting_type_string;
            $nesting_block_string_i = $nesting_block_string;
            $nesting_list_string_i  = $nesting_list_string;

            # set primary indentation levels based on structural braces
            # Note: these are set so that the leading braces have a HIGHER
            # level than their CONTENTS, which is convenient for indentation
            # Also, define continuation indentation for each token.
            if ( $type eq '{' || $type eq 'L' || $forced_indentation_flag > 0 )
            {

                # use environment before updating
                $container_environment =
                    $nesting_block_flag ? 'BLOCK'
                  : $nesting_list_flag  ? 'LIST'
                  :                       "";

                # if the difference between total nesting levels is not 1,
                # there are intervening non-structural nesting types between
                # this '{' and the previous unclosed '{'
                my $intervening_secondary_structure = 0;
                if ( @{$rslevel_stack} ) {
                    $intervening_secondary_structure =
                      $slevel_in_tokenizer - $rslevel_stack->[-1];
                }

     # Continuation Indentation
     #
     # Having tried setting continuation indentation both in the formatter and
     # in the tokenizer, I can say that setting it in the tokenizer is much,
     # much easier.  The formatter already has too much to do, and can't
     # make decisions on line breaks without knowing what 'ci' will be at
     # arbitrary locations.
     #
     # But a problem with setting the continuation indentation (ci) here
     # in the tokenizer is that we do not know where line breaks will actually
     # be.  As a result, we don't know if we should propagate continuation
     # indentation to higher levels of structure.
     #
     # For nesting of only structural indentation, we never need to do this.
     # For example, in a long if statement, like this
     #
     #   if ( !$output_block_type[$i]
     #     && ($in_statement_continuation) )
     #   {           <--outdented
     #       do_something();
     #   }
     #
     # the second line has ci but we do normally give the lines within the BLOCK
     # any ci.  This would be true if we had blocks nested arbitrarily deeply.
     #
     # But consider something like this, where we have created a break after
     # an opening paren on line 1, and the paren is not (currently) a
     # structural indentation token:
     #
     # my $file = $menubar->Menubutton(
     #   qw/-text File -underline 0 -menuitems/ => [
     #       [
     #           Cascade    => '~View',
     #           -menuitems => [
     #           ...
     #
     # The second line has ci, so it would seem reasonable to propagate it
     # down, giving the third line 1 ci + 1 indentation.  This suggests the
     # following rule, which is currently used to propagating ci down: if there
     # are any non-structural opening parens (or brackets, or braces), before
     # an opening structural brace, then ci is propagated down, and otherwise
     # not.  The variable $intervening_secondary_structure contains this
     # information for the current token, and the string
     # "$ci_string_in_tokenizer" is a stack of previous values of this
     # variable.

                # save the current states
                push( @{$rslevel_stack}, 1 + $slevel_in_tokenizer );
                $level_in_tokenizer++;

                if ( $level_in_tokenizer > $tokenizer_self->[_maximum_level_] )
                {
                    $tokenizer_self->[_maximum_level_] = $level_in_tokenizer;
                }

                if ($forced_indentation_flag) {

                    # break BEFORE '?' when there is forced indentation
                    if ( $type eq '?' ) { $level_i = $level_in_tokenizer; }
                    if ( $type eq 'k' ) {
                        $indented_if_level = $level_in_tokenizer;
                    }

                    # do not change container environment here if we are not
                    # at a real list. Adding this check prevents "blinkers"
                    # often near 'unless" clauses, such as in the following
                    # code:
##          next
##            unless -e (
##                    $archive =
##                      File::Spec->catdir( $_, "auto", $root, "$sub$lib_ext" )
##            );

                    $nesting_block_string .= "$nesting_block_flag";
                }
                else {

                    if ( $routput_block_type->[$i] ) {
                        $nesting_block_flag = 1;
                        $nesting_block_string .= '1';
                    }
                    else {
                        $nesting_block_flag = 0;
                        $nesting_block_string .= '0';
                    }
                }

                # we will use continuation indentation within containers
                # which are not blocks and not logical expressions
                my $bit = 0;
                if ( !$routput_block_type->[$i] ) {

                    # propagate flag down at nested open parens
                    if ( $routput_container_type->[$i] eq '(' ) {
                        $bit = 1 if $nesting_list_flag;
                    }

                  # use list continuation if not a logical grouping
                  # /^(if|elsif|unless|while|and|or|not|&&|!|\|\||for|foreach)$/
                    else {
                        $bit = 1
                          unless
                          $is_logical_container{ $routput_container_type->[$i]
                          };
                    }
                }
                $nesting_list_string .= $bit;
                $nesting_list_flag = $bit;

                $ci_string_in_tokenizer .=
                  ( $intervening_secondary_structure != 0 ) ? '1' : '0';
                $ci_string_sum =
                  ( my $str = $ci_string_in_tokenizer ) =~ tr/1/0/;
                $continuation_string_in_tokenizer .=
                  ( $in_statement_continuation > 0 ) ? '1' : '0';

   #  Sometimes we want to give an opening brace continuation indentation,
   #  and sometimes not.  For code blocks, we don't do it, so that the leading
   #  '{' gets outdented, like this:
   #
   #   if ( !$output_block_type[$i]
   #     && ($in_statement_continuation) )
   #   {           <--outdented
   #
   #  For other types, we will give them continuation indentation.  For example,
   #  here is how a list looks with the opening paren indented:
   #
   #     @LoL =
   #       ( [ "fred", "barney" ], [ "george", "jane", "elroy" ],
   #         [ "homer", "marge", "bart" ], );
   #
   #  This looks best when 'ci' is one-half of the indentation  (i.e., 2 and 4)

                my $total_ci = $ci_string_sum;
                if (
                    !$routput_block_type->[$i]    # patch: skip for BLOCK
                    && ($in_statement_continuation)
                    && !( $forced_indentation_flag && $type eq ':' )
                  )
                {
                    $total_ci += $in_statement_continuation
                      unless ( substr( $ci_string_in_tokenizer, -1 ) eq '1' );
                }

                $ci_string_i               = $total_ci;
                $in_statement_continuation = 0;
            }

            elsif ($type eq '}'
                || $type eq 'R'
                || $forced_indentation_flag < 0 )
            {

                # only a nesting error in the script would prevent popping here
                if ( @{$rslevel_stack} > 1 ) { pop( @{$rslevel_stack} ); }

                $level_i = --$level_in_tokenizer;

                # restore previous level values
                if ( length($nesting_block_string) > 1 )
                {    # true for valid script
                    chop $nesting_block_string;
                    $nesting_block_flag =
                      substr( $nesting_block_string, -1 ) eq '1';
                    chop $nesting_list_string;
                    $nesting_list_flag =
                      substr( $nesting_list_string, -1 ) eq '1';

                    chop $ci_string_in_tokenizer;
                    $ci_string_sum =
                      ( my $str = $ci_string_in_tokenizer ) =~ tr/1/0/;

                    $in_statement_continuation =
                      chop $continuation_string_in_tokenizer;

                    # zero continuation flag at terminal BLOCK '}' which
                    # ends a statement.
                    my $block_type_i = $routput_block_type->[$i];
                    if ($block_type_i) {

                        # ...These include non-anonymous subs
                        # note: could be sub ::abc { or sub 'abc
                        if ( $block_type_i =~ m/^sub\s*/gc ) {

                         # note: older versions of perl require the /gc modifier
                         # here or else the \G does not work.
                            if ( $block_type_i =~ /\G('|::|\w)/gc ) {
                                $in_statement_continuation = 0;
                            }
                        }

# ...and include all block types except user subs with
# block prototypes and these: (sort|grep|map|do|eval)
# /^(\}|\{|BEGIN|END|CHECK|INIT|AUTOLOAD|DESTROY|UNITCHECK|continue|;|if|elsif|else|unless|while|until|for|foreach)$/
                        elsif (
                            $is_zero_continuation_block_type{$block_type_i} )
                        {
                            $in_statement_continuation = 0;
                        }

                        # ..but these are not terminal types:
                        #     /^(sort|grep|map|do|eval)$/ )
                        elsif ($is_sort_map_grep_eval_do{$block_type_i}
                            || $is_grep_alias{$block_type_i} )
                        {
                        }

                        # ..and a block introduced by a label
                        # /^\w+\s*:$/gc ) {
                        elsif ( $block_type_i =~ /:$/ ) {
                            $in_statement_continuation = 0;
                        }

                        # user function with block prototype
                        else {
                            $in_statement_continuation = 0;
                        }
                    }

                    # If we are in a list, then
                    # we must set continuation indentation at the closing
                    # paren of something like this (paren after $check):
                    #     assert(
                    #         __LINE__,
                    #         ( not defined $check )
                    #           or ref $check
                    #           or $check eq "new"
                    #           or $check eq "old",
                    #     );
                    elsif ( $tok eq ')' ) {
                        $in_statement_continuation = 1
                          if $routput_container_type->[$i] =~ /^[;,\{\}]$/;
                    }

                    elsif ( $tok eq ';' ) { $in_statement_continuation = 0 }
                }

                # use environment after updating
                $container_environment =
                    $nesting_block_flag ? 'BLOCK'
                  : $nesting_list_flag  ? 'LIST'
                  :                       "";
                $ci_string_i = $ci_string_sum + $in_statement_continuation;
                $nesting_block_string_i = $nesting_block_string;
                $nesting_list_string_i  = $nesting_list_string;
            }

            # not a structural indentation type..
            else {

                $container_environment =
                    $nesting_block_flag ? 'BLOCK'
                  : $nesting_list_flag  ? 'LIST'
                  :                       "";

                # zero the continuation indentation at certain tokens so
                # that they will be at the same level as its container.  For
                # commas, this simplifies the -lp indentation logic, which
                # counts commas.  For ?: it makes them stand out.
                if ($nesting_list_flag) {
                    ##      $type =~ /^[,\?\:]$/
                    if ( $is_comma_question_colon{$type} ) {
                        $in_statement_continuation = 0;
                    }
                }

                # be sure binary operators get continuation indentation
                if (
                    $container_environment
                    && (   $type eq 'k' && $is_binary_keyword{$tok}
                        || $is_binary_type{$type} )
                  )
                {
                    $in_statement_continuation = 1;
                }

                # continuation indentation is sum of any open ci from previous
                # levels plus the current level
                $ci_string_i = $ci_string_sum + $in_statement_continuation;

                # update continuation flag ...
                # if this isn't a blank or comment..
                if ( $type ne 'b' && $type ne '#' ) {

                    # and we are in a BLOCK
                    if ($nesting_block_flag) {

                        # the next token after a ';' and label starts a new stmt
                        if ( $type eq ';' || $type eq 'J' ) {
                            $in_statement_continuation = 0;
                        }

                        # otherwise, we are continuing the current statement
                        else {
                            $in_statement_continuation = 1;
                        }
                    }

                    # if we are not in a BLOCK..
                    else {

                        # do not use continuation indentation if not list
                        # environment (could be within if/elsif clause)
                        if ( !$nesting_list_flag ) {
                            $in_statement_continuation = 0;
                        }

                        # otherwise, the token after a ',' starts a new term

                        # Patch FOR RT#99961; no continuation after a ';'
                        # This is needed because perltidy currently marks
                        # a block preceded by a type character like % or @
                        # as a non block, to simplify formatting. But these
                        # are actually blocks and can have semicolons.
                        # See code_block_type() and is_non_structural_brace().
                        elsif ( $type eq ',' || $type eq ';' ) {
                            $in_statement_continuation = 0;
                        }

                        # otherwise, we are continuing the current term
                        else {
                            $in_statement_continuation = 1;
                        }
                    }
                }
            }

            if ( $level_in_tokenizer < 0 ) {
                unless ( $tokenizer_self->[_saw_negative_indentation_] ) {
                    $tokenizer_self->[_saw_negative_indentation_] = 1;
                    warning("Starting negative indentation\n");
                }
            }

            # set secondary nesting levels based on all containment token types
            # Note: these are set so that the nesting depth is the depth
            # of the PREVIOUS TOKEN, which is convenient for setting
            # the strength of token bonds
            my $slevel_i = $slevel_in_tokenizer;

            #    /^[L\{\(\[]$/
            if ( $is_opening_type{$type} ) {
                $slevel_in_tokenizer++;
                $nesting_token_string .= $tok;
                $nesting_type_string  .= $type;
            }

            #       /^[R\}\)\]]$/
            elsif ( $is_closing_type{$type} ) {
                $slevel_in_tokenizer--;
                my $char = chop $nesting_token_string;

                if ( $char ne $matching_start_token{$tok} ) {
                    $nesting_token_string .= $char . $tok;
                    $nesting_type_string  .= $type;
                }
                else {
                    chop $nesting_type_string;
                }
            }

            push( @block_type,            $routput_block_type->[$i] );
            push( @ci_string,             $ci_string_i );
            push( @container_environment, $container_environment );
            push( @container_type,        $routput_container_type->[$i] );
            push( @levels,                $level_i );
            push( @nesting_tokens,        $nesting_token_string_i );
            push( @nesting_types,         $nesting_type_string_i );
            push( @slevels,               $slevel_i );
            push( @token_type,            $fix_type );
            push( @type_sequence,         $routput_type_sequence->[$i] );
            push( @nesting_blocks,        $nesting_block_string );
            push( @nesting_lists,         $nesting_list_string );

            # now form the previous token
            if ( $im >= 0 ) {
                $num =
                  $rtoken_map->[$i] - $rtoken_map->[$im];  # how many characters

                if ( $num > 0 ) {
                    push( @tokens,
                        substr( $input_line, $rtoken_map->[$im], $num ) );
                }
            }
            $im = $i;
        }

        $num = length($input_line) - $rtoken_map->[$im];   # make the last token
        if ( $num > 0 ) {
            push( @tokens, substr( $input_line, $rtoken_map->[$im], $num ) );
        }

        $tokenizer_self->[_in_attribute_list_] = $in_attribute_list;
        $tokenizer_self->[_in_quote_]          = $in_quote;
        $tokenizer_self->[_quote_target_] =
          $in_quote ? matching_end_token($quote_character) : "";
        $tokenizer_self->[_rhere_target_list_] = $rhere_target_list;

        $line_of_tokens->{_rtoken_type}            = \@token_type;
        $line_of_tokens->{_rtokens}                = \@tokens;
        $line_of_tokens->{_rblock_type}            = \@block_type;
        $line_of_tokens->{_rcontainer_type}        = \@container_type;
        $line_of_tokens->{_rcontainer_environment} = \@container_environment;
        $line_of_tokens->{_rtype_sequence}         = \@type_sequence;
        $line_of_tokens->{_rlevels}                = \@levels;
        $line_of_tokens->{_rslevels}               = \@slevels;
        $line_of_tokens->{_rnesting_tokens}        = \@nesting_tokens;
        $line_of_tokens->{_rci_levels}             = \@ci_string;
        $line_of_tokens->{_rnesting_blocks}        = \@nesting_blocks;

        return;
    }
} ## end tokenize_this_line

#########i#############################################################
# Tokenizer routines which assist in identifying token types
#######################################################################

# hash lookup table of operator expected values
my %op_expected_table;

# exceptions to perl's weird parsing rules after type 'Z'
my %is_weird_parsing_rule_exception;

my %is_paren_dollar;

my %is_n_v;

BEGIN {

    # Always expecting TERM following these types:
    # note: this is identical to '@value_requestor_type' defined later.
    my @q = qw(
      ; ! + x & ?  F J - p / Y : % f U ~ A G j L * . | ^ < = [ m { \ > t
      || >= != mm *= => .. !~ == && |= .= pp -= =~ += <= %= ^= x= ~~ ** << /=
      &= // >> ~. &. |. ^.
      ... **= <<= >>= &&= ||= //= <=> !~~ &.= |.= ^.= <<~
    );
    push @q, ',';
    push @q, '(';    # for completeness, not currently a token type
    @{op_expected_table}{@q} = (TERM) x scalar(@q);

    # Always UNKNOWN following these types:
    # Fix for c030: added '->' to this list
    @q = qw( w -> );
    @{op_expected_table}{@q} = (UNKNOWN) x scalar(@q);

    # Always expecting OPERATOR ...
    # 'n' and 'v' are currently excluded because they might be VERSION numbers
    # 'i' is currently excluded because it might be a package
    # 'q' is currently excluded because it might be a prototype
    # Fix for c030: removed '->' from this list:
    @q = qw( -- C h R ++ ] Q <> );    ## n v q i );
    push @q, ')';
    @{op_expected_table}{@q} = (OPERATOR) x scalar(@q);

    # Fix for git #62: added '*' and '%'
    @q = qw( < ? * % );
    @{is_weird_parsing_rule_exception}{@q} = (1) x scalar(@q);

    @q = qw<) $>;
    @{is_paren_dollar}{@q} = (1) x scalar(@q);

    @q = qw( n v );
    @{is_n_v}{@q} = (1) x scalar(@q);

}

use constant DEBUG_OPERATOR_EXPECTED => 0;

sub operator_expected {

    # Returns a parameter indicating what types of tokens can occur next

    # Call format:
    #    $op_expected = operator_expected( [ $prev_type, $tok, $next_type ] );
    # where
    #    $prev_type is the type of the previous token (blank or not)
    #    $tok is the current token
    #    $next_type is the type of the next token (blank or not)

    # Many perl symbols have two or more meanings.  For example, '<<'
    # can be a shift operator or a here-doc operator.  The
    # interpretation of these symbols depends on the current state of
    # the tokenizer, which may either be expecting a term or an
    # operator.  For this example, a << would be a shift if an OPERATOR
    # is expected, and a here-doc if a TERM is expected.  This routine
    # is called to make this decision for any current token.  It returns
    # one of three possible values:
    #
    #     OPERATOR - operator expected (or at least, not a term)
    #     UNKNOWN  - can't tell
    #     TERM     - a term is expected (or at least, not an operator)
    #
    # The decision is based on what has been seen so far.  This
    # information is stored in the "$last_nonblank_type" and
    # "$last_nonblank_token" variables.  For example, if the
    # $last_nonblank_type is '=~', then we are expecting a TERM, whereas
    # if $last_nonblank_type is 'n' (numeric), we are expecting an
    # OPERATOR.
    #
    # If a UNKNOWN is returned, the calling routine must guess. A major
    # goal of this tokenizer is to minimize the possibility of returning
    # UNKNOWN, because a wrong guess can spoil the formatting of a
    # script.
    #
    # Adding NEW_TOKENS: it is critically important that this routine be
    # updated to allow it to determine if an operator or term is to be
    # expected after the new token.  Doing this simply involves adding
    # the new token character to one of the regexes in this routine or
    # to one of the hash lists
    # that it uses, which are initialized in the BEGIN section.
    # USES GLOBAL VARIABLES: $last_nonblank_type, $last_nonblank_token,
    # $statement_type

    # When possible, token types should be selected such that we can determine
    # the 'operator_expected' value by a simple hash lookup.  If there are
    # exceptions, that is an indication that a new type is needed.

    my ($rarg) = @_;

    my $msg = "";

    ##############
    # Table lookup
    ##############

    # Many types are can be obtained by a table lookup given the previous type.
    # This typically handles half or more of the calls.
    my $op_expected = $op_expected_table{$last_nonblank_type};
    if ( defined($op_expected) ) {
        $msg = "Table lookup";
        goto RETURN;
    }

    ######################
    # Handle special cases
    ######################

    $op_expected = UNKNOWN;
    my ( $prev_type, $tok, $next_type ) = @{$rarg};

    # Types 'k', '}' and 'Z' depend on context
    # FIXME: Types 'i', 'n', 'v', 'q' currently also temporarily depend on
    # context but that dependence could eventually be eliminated with better
    # token type definition

    # identifier...
    if ( $last_nonblank_type eq 'i' ) {
        $op_expected = OPERATOR;

        # FIXME: it would be cleaner to make this a special type
        # expecting VERSION or {} after package NAMESPACE
        # TODO: maybe mark these words as type 'Y'?
        if (   substr( $last_nonblank_token, 0, 7 ) eq 'package'
            && $statement_type      =~ /^package\b/
            && $last_nonblank_token =~ /^package\b/ )
        {
            $op_expected = TERM;
        }
    }

    # keyword...
    elsif ( $last_nonblank_type eq 'k' ) {
        $op_expected = TERM;
        if ( $expecting_operator_token{$last_nonblank_token} ) {
            $op_expected = OPERATOR;
        }
        elsif ( $expecting_term_token{$last_nonblank_token} ) {

            # Exceptions from TERM:

            # // may follow perl functions which may be unary operators
            # see test file dor.t (defined or);
            if (
                   $tok eq '/'
                && $next_type eq '/'
                && $is_keyword_rejecting_slash_as_pattern_delimiter{
                    $last_nonblank_token}
              )
            {
                $op_expected = OPERATOR;
            }

            # Patch to allow a ? following 'split' to be a depricated pattern
            # delimiter.  This patch is coordinated with the omission of split
            # from the list
            # %is_keyword_rejecting_question_as_pattern_delimiter. This patch
            # will force perltidy to guess.
            elsif ($tok eq '?'
                && $last_nonblank_token eq 'split' )
            {
                $op_expected = UNKNOWN;
            }
        }
    } ## end type 'k'

    # closing container token...

    # Note that the actual token for type '}' may also be a ')'.

    # Also note that $last_nonblank_token is not the token corresponding to
    # $last_nonblank_type when the type is a closing container.  In that
    # case it is the token before the corresponding opening container token.
    # So for example, for this snippet
    #       $a = do { BLOCK } / 2;
    # the $last_nonblank_token is 'do' when $last_nonblank_type eq '}'.

    elsif ( $last_nonblank_type eq '}' ) {
        $op_expected = UNKNOWN;

        # handle something after 'do' and 'eval'
        if ( $is_block_operator{$last_nonblank_token} ) {

            # something like $a = do { BLOCK } / 2;
            $op_expected = OPERATOR;    # block mode following }
        }

        ##elsif ( $last_nonblank_token =~ /^(\)|\$|\-\>)/ ) {
        elsif ( $is_paren_dollar{ substr( $last_nonblank_token, 0, 1 ) }
            || substr( $last_nonblank_token, 0, 2 ) eq '->' )
        {
            $op_expected = OPERATOR;
            if ( $last_nonblank_token eq '$' ) { $op_expected = UNKNOWN }
        }

        # Check for smartmatch operator before preceding brace or square
        # bracket.  For example, at the ? after the ] in the following
        # expressions we are expecting an operator:
        #
        # qr/3/ ~~ ['1234'] ? 1 : 0;
        # map { $_ ~~ [ '0', '1' ] ? 'x' : 'o' } @a;
        elsif ( $last_nonblank_token eq '~~' ) {
            $op_expected = OPERATOR;
        }

        # A right brace here indicates the end of a simple block.  All
        # non-structural right braces have type 'R' all braces associated with
        # block operator keywords have been given those keywords as
        # "last_nonblank_token" and caught above.  (This statement is order
        # dependent, and must come after checking $last_nonblank_token).
        else {

            # patch for dor.t (defined or).
            if (   $tok eq '/'
                && $next_type eq '/'
                && $last_nonblank_token eq ']' )
            {
                $op_expected = OPERATOR;
            }

            # Patch for RT #116344: misparse a ternary operator after an
            # anonymous hash, like this:
            #   return ref {} ? 1 : 0;
            # The right brace should really be marked type 'R' in this case,
            # and it is safest to return an UNKNOWN here. Expecting a TERM will
            # cause the '?' to always be interpreted as a pattern delimiter
            # rather than introducing a ternary operator.
            elsif ( $tok eq '?' ) {
                $op_expected = UNKNOWN;
            }
            else {
                $op_expected = TERM;
            }
        }
    } ## end type '}'

    # number or v-string...
    # An exception is for VERSION numbers a 'use' statement. It has the format
    #     use Module VERSION LIST
    # We could avoid this exception by writing a special sub to parse 'use'
    # statements and perhaps mark these numbers with a new type V (for VERSION)
    ##elsif ( $last_nonblank_type =~ /^[nv]$/ ) {
    elsif ( $is_n_v{$last_nonblank_type} ) {
        $op_expected = OPERATOR;
        if ( $statement_type eq 'use' ) {
            $op_expected = UNKNOWN;
        }
    }

    # quote...
    # FIXME: labeled prototype words should probably be given type 'A' or maybe
    # 'J'; not 'q'; or maybe mark as type 'Y'
    elsif ( $last_nonblank_type eq 'q' ) {
        $op_expected = OPERATOR;
        if ( $last_nonblank_token eq 'prototype' )
          ##|| $last_nonblank_token eq 'switch' )
        {
            $op_expected = TERM;
        }
    }

    # file handle or similar
    elsif ( $last_nonblank_type eq 'Z' ) {

        $op_expected = UNKNOWN;

        # angle.t
        if ( $last_nonblank_token =~ /^\w/ ) {
            $op_expected = UNKNOWN;
        }

        # Exception to weird parsing rules for 'x(' ... see case b1205:
        # In something like 'print $vv x(...' the x is an operator;
        # Likewise in 'print $vv x$ww' the x is an operatory (case b1207)
        # otherwise x follows the weird parsing rules.
        elsif ( $tok eq 'x' && $next_type =~ /^[\(\$\@\%]$/ ) {
            $op_expected = OPERATOR;
        }

        # The 'weird parsing rules' of next section do not work for '<' and '?'
        # It is best to mark them as unknown.  Test case:
        #  print $fh <DATA>;
        elsif ( $is_weird_parsing_rule_exception{$tok} ) {
            $op_expected = UNKNOWN;
        }

        # For possible file handle like "$a", Perl uses weird parsing rules.
        # For example:
        # print $a/2,"/hi";   - division
        # print $a / 2,"/hi"; - division
        # print $a/ 2,"/hi";  - division
        # print $a /2,"/hi";  - pattern (and error)!
        # Some examples where this logic works okay, for '&','*','+':
        #    print $fh &xsi_protos(@mods);
        #    my $x = new $CompressClass *FH;
        #    print $OUT +( $count % 15 ? ", " : "\n\t" );
        elsif ($prev_type eq 'b'
            && $next_type ne 'b' )
        {
            $op_expected = TERM;
        }

        # Note that '?' and '<' have been moved above
        # ( $tok =~ /^([x\/\+\-\*\%\&\.\?\<]|\>\>)$/ ) {
        elsif ( $tok =~ /^([x\/\+\-\*\%\&\.]|\>\>)$/ ) {

            # Do not complain in 'use' statements, which have special syntax.
            # For example, from RT#130344:
            #   use lib $FindBin::Bin . '/lib';
            if ( $statement_type ne 'use' ) {
                complain(
"operator in possible indirect object location not recommended\n"
                );
            }
            $op_expected = OPERATOR;
        }
    }

    # anything else...
    else {
        $op_expected = UNKNOWN;
    }

  RETURN:

    DEBUG_OPERATOR_EXPECTED && do {
        print STDOUT
"OPERATOR_EXPECTED: $msg: returns $op_expected for last type $last_nonblank_type token $last_nonblank_token\n";
    };

    return $op_expected;

} ## end of sub operator_expected

sub new_statement_ok {

    # return true if the current token can start a new statement
    # USES GLOBAL VARIABLES: $last_nonblank_type

    return label_ok()    # a label would be ok here

      || $last_nonblank_type eq 'J';    # or we follow a label

}

sub label_ok {

    # Decide if a bare word followed by a colon here is a label
    # USES GLOBAL VARIABLES: $last_nonblank_token, $last_nonblank_type,
    # $brace_depth, @brace_type

    # if it follows an opening or closing code block curly brace..
    if ( ( $last_nonblank_token eq '{' || $last_nonblank_token eq '}' )
        && $last_nonblank_type eq $last_nonblank_token )
    {

        # it is a label if and only if the curly encloses a code block
        return $brace_type[$brace_depth];
    }

    # otherwise, it is a label if and only if it follows a ';' (real or fake)
    # or another label
    else {
        return ( $last_nonblank_type eq ';' || $last_nonblank_type eq 'J' );
    }
}

sub code_block_type {

    # Decide if this is a block of code, and its type.
    # Must be called only when $type = $token = '{'
    # The problem is to distinguish between the start of a block of code
    # and the start of an anonymous hash reference
    # Returns "" if not code block, otherwise returns 'last_nonblank_token'
    # to indicate the type of code block.  (For example, 'last_nonblank_token'
    # might be 'if' for an if block, 'else' for an else block, etc).
    # USES GLOBAL VARIABLES: $last_nonblank_token, $last_nonblank_type,
    # $last_nonblank_block_type, $brace_depth, @brace_type

    # handle case of multiple '{'s

# print "BLOCK_TYPE EXAMINING: type=$last_nonblank_type tok=$last_nonblank_token\n";

    my ( $i, $rtokens, $rtoken_type, $max_token_index ) = @_;
    if (   $last_nonblank_token eq '{'
        && $last_nonblank_type eq $last_nonblank_token )
    {

        # opening brace where a statement may appear is probably
        # a code block but might be and anonymous hash reference
        if ( $brace_type[$brace_depth] ) {
            return decide_if_code_block( $i, $rtokens, $rtoken_type,
                $max_token_index );
        }

        # cannot start a code block within an anonymous hash
        else {
            return "";
        }
    }

    elsif ( $last_nonblank_token eq ';' ) {

        # an opening brace where a statement may appear is probably
        # a code block but might be and anonymous hash reference
        return decide_if_code_block( $i, $rtokens, $rtoken_type,
            $max_token_index );
    }

    # handle case of '}{'
    elsif ($last_nonblank_token eq '}'
        && $last_nonblank_type eq $last_nonblank_token )
    {

        # a } { situation ...
        # could be hash reference after code block..(blktype1.t)
        if ($last_nonblank_block_type) {
            return decide_if_code_block( $i, $rtokens, $rtoken_type,
                $max_token_index );
        }

        # must be a block if it follows a closing hash reference
        else {
            return $last_nonblank_token;
        }
    }

    ################################################################
    # NOTE: braces after type characters start code blocks, but for
    # simplicity these are not identified as such.  See also
    # sub is_non_structural_brace.
    ################################################################

##    elsif ( $last_nonblank_type eq 't' ) {
##       return $last_nonblank_token;
##    }

    # brace after label:
    elsif ( $last_nonblank_type eq 'J' ) {
        return $last_nonblank_token;
    }

# otherwise, look at previous token.  This must be a code block if
# it follows any of these:
# /^(BEGIN|END|CHECK|INIT|AUTOLOAD|DESTROY|UNITCHECK|continue|if|elsif|else|unless|do|while|until|eval|for|foreach|map|grep|sort)$/
    elsif ($is_code_block_token{$last_nonblank_token}
        || $is_grep_alias{$last_nonblank_token} )
    {

        # Bug Patch: Note that the opening brace after the 'if' in the following
        # snippet is an anonymous hash ref and not a code block!
        #   print 'hi' if { x => 1, }->{x};
        # We can identify this situation because the last nonblank type
        # will be a keyword (instead of a closing peren)
        if (   $last_nonblank_token =~ /^(if|unless)$/
            && $last_nonblank_type eq 'k' )
        {
            return "";
        }
        else {
            return $last_nonblank_token;
        }
    }

    # or a sub or package BLOCK
    elsif ( ( $last_nonblank_type eq 'i' || $last_nonblank_type eq 't' )
        && $last_nonblank_token =~ /^(sub|package)\b/ )
    {
        return $last_nonblank_token;
    }

    # or a sub alias
    elsif (( $last_nonblank_type eq 'i' || $last_nonblank_type eq 't' )
        && ( $is_sub{$last_nonblank_token} ) )
    {
        return 'sub';
    }

    elsif ( $statement_type =~ /^(sub|package)\b/ ) {
        return $statement_type;
    }

    # user-defined subs with block parameters (like grep/map/eval)
    elsif ( $last_nonblank_type eq 'G' ) {
        return $last_nonblank_token;
    }

    # check bareword
    elsif ( $last_nonblank_type eq 'w' ) {

        # check for syntax 'use MODULE LIST'
        # This fixes b1022 b1025 b1027 b1028 b1029 b1030 b1031
        return "" if ( $statement_type eq 'use' );

        return decide_if_code_block( $i, $rtokens, $rtoken_type,
            $max_token_index );
    }

    # Patch for bug # RT #94338 reported by Daniel Trizen
    # for-loop in a parenthesized block-map triggering an error message:
    #    map( { foreach my $item ( '0', '1' ) { print $item} } qw(a b c) );
    # Check for a code block within a parenthesized function call
    elsif ( $last_nonblank_token eq '(' ) {
        my $paren_type = $paren_type[$paren_depth];
        if ( $paren_type && $paren_type =~ /^(map|grep|sort)$/ ) {

            # We will mark this as a code block but use type 't' instead
            # of the name of the contining function.  This will allow for
            # correct parsing but will usually produce better formatting.
            # Braces with block type 't' are not broken open automatically
            # in the formatter as are other code block types, and this usually
            # works best.
            return 't';    # (Not $paren_type)
        }
        else {
            return "";
        }
    }

    # handle unknown syntax ') {'
    # we previously appended a '()' to mark this case
    elsif ( $last_nonblank_token =~ /\(\)$/ ) {
        return $last_nonblank_token;
    }

    # anything else must be anonymous hash reference
    else {
        return "";
    }
}

sub decide_if_code_block {

    # USES GLOBAL VARIABLES: $last_nonblank_token
    my ( $i, $rtokens, $rtoken_type, $max_token_index ) = @_;

    my ( $next_nonblank_token, $i_next ) =
      find_next_nonblank_token( $i, $rtokens, $max_token_index );

    # we are at a '{' where a statement may appear.
    # We must decide if this brace starts an anonymous hash or a code
    # block.
    # return "" if anonymous hash, and $last_nonblank_token otherwise

    # initialize to be code BLOCK
    my $code_block_type = $last_nonblank_token;

    # Check for the common case of an empty anonymous hash reference:
    # Maybe something like sub { { } }
    if ( $next_nonblank_token eq '}' ) {
        $code_block_type = "";
    }

    else {

        # To guess if this '{' is an anonymous hash reference, look ahead
        # and test as follows:
        #
        # it is a hash reference if next come:
        #   - a string or digit followed by a comma or =>
        #   - bareword followed by =>
        # otherwise it is a code block
        #
        # Examples of anonymous hash ref:
        # {'aa',};
        # {1,2}
        #
        # Examples of code blocks:
        # {1; print "hello\n", 1;}
        # {$a,1};

        # We are only going to look ahead one more (nonblank/comment) line.
        # Strange formatting could cause a bad guess, but that's unlikely.
        my @pre_types;
        my @pre_tokens;

        # Ignore the rest of this line if it is a side comment
        if ( $next_nonblank_token ne '#' ) {
            @pre_types  = @{$rtoken_type}[ $i + 1 .. $max_token_index ];
            @pre_tokens = @{$rtokens}[ $i + 1 .. $max_token_index ];
        }
        my ( $rpre_tokens, $rpre_types ) =
          peek_ahead_for_n_nonblank_pre_tokens(20);    # 20 is arbitrary but
                                                       # generous, and prevents
                                                       # wasting lots of
                                                       # time in mangled files
        if ( defined($rpre_types) && @{$rpre_types} ) {
            push @pre_types,  @{$rpre_types};
            push @pre_tokens, @{$rpre_tokens};
        }

        # put a sentinel token to simplify stopping the search
        push @pre_types, '}';
        push @pre_types, '}';

        my $jbeg = 0;
        $jbeg = 1 if $pre_types[0] eq 'b';

        # first look for one of these
        #  - bareword
        #  - bareword with leading -
        #  - digit
        #  - quoted string
        my $j = $jbeg;
        if ( $pre_types[$j] =~ /^[\'\"]/ ) {

            # find the closing quote; don't worry about escapes
            my $quote_mark = $pre_types[$j];
            foreach my $k ( $j + 1 .. @pre_types - 2 ) {
                if ( $pre_types[$k] eq $quote_mark ) {
                    $j = $k + 1;
                    my $next = $pre_types[$j];
                    last;
                }
            }
        }
        elsif ( $pre_types[$j] eq 'd' ) {
            $j++;
        }
        elsif ( $pre_types[$j] eq 'w' ) {
            $j++;
        }
        elsif ( $pre_types[$j] eq '-' && $pre_types[ ++$j ] eq 'w' ) {
            $j++;
        }
        if ( $j > $jbeg ) {

            $j++ if $pre_types[$j] eq 'b';

            # Patched for RT #95708
            if (

                # it is a comma which is not a pattern delimeter except for qw
                (
                       $pre_types[$j] eq ','
                    && $pre_tokens[$jbeg] !~ /^(s|m|y|tr|qr|q|qq|qx)$/
                )

                # or a =>
                || ( $pre_types[$j] eq '=' && $pre_types[ ++$j ] eq '>' )
              )
            {
                $code_block_type = "";
            }
        }

        if ($code_block_type) {

            # Patch for cases b1085 b1128: It is uncertain if this is a block.
            # If this brace follows a bareword, then append a space as a signal
            # to the formatter that this may not be a block brace.  To find the
            # corresponding code in Formatter.pm search for 'b1085'.
            $code_block_type .= " " if ( $code_block_type =~ /^\w/ );
        }
    }

    return $code_block_type;
}

sub report_unexpected {

    # report unexpected token type and show where it is
    # USES GLOBAL VARIABLES: $tokenizer_self
    my ( $found, $expecting, $i_tok, $last_nonblank_i, $rpretoken_map,
        $rpretoken_type, $input_line )
      = @_;

    if ( ++$tokenizer_self->[_unexpected_error_count_] <= MAX_NAG_MESSAGES ) {
        my $msg = "found $found where $expecting expected";
        my $pos = $rpretoken_map->[$i_tok];
        interrupt_logfile();
        my $input_line_number = $tokenizer_self->[_last_line_number_];
        my ( $offset, $numbered_line, $underline ) =
          make_numbered_line( $input_line_number, $input_line, $pos );
        $underline = write_on_underline( $underline, $pos - $offset, '^' );

        my $trailer = "";
        if ( ( $i_tok > 0 ) && ( $last_nonblank_i >= 0 ) ) {
            my $pos_prev = $rpretoken_map->[$last_nonblank_i];
            my $num;
            if ( $rpretoken_type->[ $i_tok - 1 ] eq 'b' ) {
                $num = $rpretoken_map->[ $i_tok - 1 ] - $pos_prev;
            }
            else {
                $num = $pos - $pos_prev;
            }
            if ( $num > 40 ) { $num = 40; $pos_prev = $pos - 40; }

            $underline =
              write_on_underline( $underline, $pos_prev - $offset, '-' x $num );
            $trailer = " (previous token underlined)";
        }
        $underline =~ s/\s+$//;
        warning( $numbered_line . "\n" );
        warning( $underline . "\n" );
        warning( $msg . $trailer . "\n" );
        resume_logfile();
    }
    return;
}

my %is_sigil_or_paren;
my %is_R_closing_sb;

BEGIN {

    my @q = qw< $ & % * @ ) >;
    @{is_sigil_or_paren}{@q} = (1) x scalar(@q);

    @q = qw(R ]);
    @{is_R_closing_sb}{@q} = (1) x scalar(@q);
}

sub is_non_structural_brace {

    # Decide if a brace or bracket is structural or non-structural
    # by looking at the previous token and type
    # USES GLOBAL VARIABLES: $last_nonblank_type, $last_nonblank_token

    # EXPERIMENTAL: Mark slices as structural; idea was to improve formatting.
    # Tentatively deactivated because it caused the wrong operator expectation
    # for this code:
    #      $user = @vars[1] / 100;
    # Must update sub operator_expected before re-implementing.
    # if ( $last_nonblank_type eq 'i' && $last_nonblank_token =~ /^@/ ) {
    #    return 0;
    # }

    ################################################################
    # NOTE: braces after type characters start code blocks, but for
    # simplicity these are not identified as such.  See also
    # sub code_block_type
    ################################################################

    ##if ($last_nonblank_type eq 't') {return 0}

    # otherwise, it is non-structural if it is decorated
    # by type information.
    # For example, the '{' here is non-structural:   ${xxx}
    # Removed '::' to fix c074
    ## $last_nonblank_token =~ /^([\$\@\*\&\%\)]|->|::)/
    return (
        ## $last_nonblank_token =~ /^([\$\@\*\&\%\)]|->)/
        $is_sigil_or_paren{ substr( $last_nonblank_token, 0, 1 ) }
          || substr( $last_nonblank_token, 0, 2 ) eq '->'

          # or if we follow a hash or array closing curly brace or bracket
          # For example, the second '{' in this is non-structural: $a{'x'}{'y'}
          # because the first '}' would have been given type 'R'
          ##|| $last_nonblank_type =~ /^([R\]])$/
          || $is_R_closing_sb{$last_nonblank_type}
    );
}

#########i#############################################################
# Tokenizer routines for tracking container nesting depths
#######################################################################

# The following routines keep track of nesting depths of the nesting
# types, ( [ { and ?.  This is necessary for determining the indentation
# level, and also for debugging programs.  Not only do they keep track of
# nesting depths of the individual brace types, but they check that each
# of the other brace types is balanced within matching pairs.  For
# example, if the program sees this sequence:
#
#         {  ( ( ) }
#
# then it can determine that there is an extra left paren somewhere
# between the { and the }.  And so on with every other possible
# combination of outer and inner brace types.  For another
# example:
#
#         ( [ ..... ]  ] )
#
# which has an extra ] within the parens.
#
# The brace types have indexes 0 .. 3 which are indexes into
# the matrices.
#
# The pair ? : are treated as just another nesting type, with ? acting
# as the opening brace and : acting as the closing brace.
#
# The matrix
#
#         $depth_array[$a][$b][ $current_depth[$a] ] = $current_depth[$b];
#
# saves the nesting depth of brace type $b (where $b is either of the other
# nesting types) when brace type $a enters a new depth.  When this depth
# decreases, a check is made that the current depth of brace types $b is
# unchanged, or otherwise there must have been an error.  This can
# be very useful for localizing errors, particularly when perl runs to
# the end of a large file (such as this one) and announces that there
# is a problem somewhere.
#
# A numerical sequence number is maintained for every nesting type,
# so that each matching pair can be uniquely identified in a simple
# way.

sub increase_nesting_depth {
    my ( $aa, $pos ) = @_;

    # USES GLOBAL VARIABLES: $tokenizer_self, @current_depth,
    # @current_sequence_number, @depth_array, @starting_line_of_current_depth,
    # $statement_type
    $current_depth[$aa]++;
    $total_depth++;
    $total_depth[$aa][ $current_depth[$aa] ] = $total_depth;
    my $input_line_number = $tokenizer_self->[_last_line_number_];
    my $input_line        = $tokenizer_self->[_line_of_text_];

    # Sequence numbers increment by number of items.  This keeps
    # a unique set of numbers but still allows the relative location
    # of any type to be determined.

    ########################################################################
    # OLD SEQNO METHOD for incrementing sequence numbers.
    # Keep this coding awhile for possible testing.
    ## $nesting_sequence_number[$aa] += scalar(@closing_brace_names);
    ## my $seqno = $nesting_sequence_number[$aa];

    # NEW SEQNO METHOD, continuous sequence numbers. This allows sequence
    # numbers to be used as array indexes, and allows them to be compared.
    my $seqno = $next_sequence_number++;
    ########################################################################

    $current_sequence_number[$aa][ $current_depth[$aa] ] = $seqno;

    $starting_line_of_current_depth[$aa][ $current_depth[$aa] ] =
      [ $input_line_number, $input_line, $pos ];

    for my $bb ( 0 .. @closing_brace_names - 1 ) {
        next if ( $bb == $aa );
        $depth_array[$aa][$bb][ $current_depth[$aa] ] = $current_depth[$bb];
    }

    # set a flag for indenting a nested ternary statement
    my $indent = 0;
    if ( $aa == QUESTION_COLON ) {
        $nested_ternary_flag[ $current_depth[$aa] ] = 0;
        if ( $current_depth[$aa] > 1 ) {
            if ( $nested_ternary_flag[ $current_depth[$aa] - 1 ] == 0 ) {
                my $pdepth = $total_depth[$aa][ $current_depth[$aa] - 1 ];
                if ( $pdepth == $total_depth - 1 ) {
                    $indent = 1;
                    $nested_ternary_flag[ $current_depth[$aa] - 1 ] = -1;
                }
            }
        }
    }
    $nested_statement_type[$aa][ $current_depth[$aa] ] = $statement_type;
    $statement_type = "";
    return ( $seqno, $indent );
}

sub is_balanced_closing_container {

    # Return true if a closing container can go here without error
    # Return false if not
    my ($aa) = @_;

    # cannot close if there was no opening
    return unless ( $current_depth[$aa] > 0 );

    # check that any other brace types $bb contained within would be balanced
    for my $bb ( 0 .. @closing_brace_names - 1 ) {
        next if ( $bb == $aa );
        return
          unless ( $depth_array[$aa][$bb][ $current_depth[$aa] ] ==
            $current_depth[$bb] );
    }

    # OK, everything will be balanced
    return 1;
}

sub decrease_nesting_depth {

    my ( $aa, $pos ) = @_;

    # USES GLOBAL VARIABLES: $tokenizer_self, @current_depth,
    # @current_sequence_number, @depth_array, @starting_line_of_current_depth
    # $statement_type
    my $seqno             = 0;
    my $input_line_number = $tokenizer_self->[_last_line_number_];
    my $input_line        = $tokenizer_self->[_line_of_text_];

    my $outdent = 0;
    $total_depth--;
    if ( $current_depth[$aa] > 0 ) {

        # set a flag for un-indenting after seeing a nested ternary statement
        $seqno = $current_sequence_number[$aa][ $current_depth[$aa] ];
        if ( $aa == QUESTION_COLON ) {
            $outdent = $nested_ternary_flag[ $current_depth[$aa] ];
        }
        $statement_type = $nested_statement_type[$aa][ $current_depth[$aa] ];

        # check that any brace types $bb contained within are balanced
        for my $bb ( 0 .. @closing_brace_names - 1 ) {
            next if ( $bb == $aa );

            unless ( $depth_array[$aa][$bb][ $current_depth[$aa] ] ==
                $current_depth[$bb] )
            {
                my $diff =
                  $current_depth[$bb] -
                  $depth_array[$aa][$bb][ $current_depth[$aa] ];

                # don't whine too many times
                my $saw_brace_error = get_saw_brace_error();
                if (
                    $saw_brace_error <= MAX_NAG_MESSAGES

                    # if too many closing types have occurred, we probably
                    # already caught this error
                    && ( ( $diff > 0 ) || ( $saw_brace_error <= 0 ) )
                  )
                {
                    interrupt_logfile();
                    my $rsl =
                      $starting_line_of_current_depth[$aa]
                      [ $current_depth[$aa] ];
                    my $sl  = $rsl->[0];
                    my $rel = [ $input_line_number, $input_line, $pos ];
                    my $el  = $rel->[0];
                    my ($ess);

                    if ( $diff == 1 || $diff == -1 ) {
                        $ess = '';
                    }
                    else {
                        $ess = 's';
                    }
                    my $bname =
                      ( $diff > 0 )
                      ? $opening_brace_names[$bb]
                      : $closing_brace_names[$bb];
                    write_error_indicator_pair( @{$rsl}, '^' );
                    my $msg = <<"EOM";
Found $diff extra $bname$ess between $opening_brace_names[$aa] on line $sl and $closing_brace_names[$aa] on line $el
EOM

                    if ( $diff > 0 ) {
                        my $rml =
                          $starting_line_of_current_depth[$bb]
                          [ $current_depth[$bb] ];
                        my $ml = $rml->[0];
                        $msg .=
"    The most recent un-matched $bname is on line $ml\n";
                        write_error_indicator_pair( @{$rml}, '^' );
                    }
                    write_error_indicator_pair( @{$rel}, '^' );
                    warning($msg);
                    resume_logfile();
                }
                increment_brace_error();
            }
        }
        $current_depth[$aa]--;
    }
    else {

        my $saw_brace_error = get_saw_brace_error();
        if ( $saw_brace_error <= MAX_NAG_MESSAGES ) {
            my $msg = <<"EOM";
There is no previous $opening_brace_names[$aa] to match a $closing_brace_names[$aa] on line $input_line_number
EOM
            indicate_error( $msg, $input_line_number, $input_line, $pos, '^' );
        }
        increment_brace_error();

        # keep track of errors in braces alone (ignoring ternary nesting errors)
        $tokenizer_self->[_true_brace_error_count_]++
          if ( $closing_brace_names[$aa] ne "':'" );
    }
    return ( $seqno, $outdent );
}

sub check_final_nesting_depths {

    # USES GLOBAL VARIABLES: @current_depth, @starting_line_of_current_depth

    for my $aa ( 0 .. @closing_brace_names - 1 ) {

        if ( $current_depth[$aa] ) {
            my $rsl =
              $starting_line_of_current_depth[$aa][ $current_depth[$aa] ];
            my $sl  = $rsl->[0];
            my $msg = <<"EOM";
Final nesting depth of $opening_brace_names[$aa]s is $current_depth[$aa]
The most recent un-matched $opening_brace_names[$aa] is on line $sl
EOM
            indicate_error( $msg, @{$rsl}, '^' );
            increment_brace_error();
        }
    }
    return;
}

#########i#############################################################
# Tokenizer routines for looking ahead in input stream
#######################################################################

sub peek_ahead_for_n_nonblank_pre_tokens {

    # returns next n pretokens if they exist
    # returns undef's if hits eof without seeing any pretokens
    # USES GLOBAL VARIABLES: $tokenizer_self
    my $max_pretokens = shift;
    my $line;
    my $i = 0;
    my ( $rpre_tokens, $rmap, $rpre_types );

    while ( $line =
        $tokenizer_self->[_line_buffer_object_]->peek_ahead( $i++ ) )
    {
        $line =~ s/^\s*//;                 # trim leading blanks
        next if ( length($line) <= 0 );    # skip blank
        next if ( $line =~ /^#/ );         # skip comment
        ( $rpre_tokens, $rmap, $rpre_types ) =
          pre_tokenize( $line, $max_pretokens );
        last;
    }
    return ( $rpre_tokens, $rpre_types );
}

# look ahead for next non-blank, non-comment line of code
sub peek_ahead_for_nonblank_token {

    # USES GLOBAL VARIABLES: $tokenizer_self
    my ( $rtokens, $max_token_index ) = @_;
    my $line;
    my $i = 0;

    while ( $line =
        $tokenizer_self->[_line_buffer_object_]->peek_ahead( $i++ ) )
    {
        $line =~ s/^\s*//;                 # trim leading blanks
        next if ( length($line) <= 0 );    # skip blank
        next if ( $line =~ /^#/ );         # skip comment

        # Updated from 2 to 3 to get trigraphs, added for case b1175
        my ( $rtok, $rmap, $rtype ) = pre_tokenize( $line, 3 );
        my $j = $max_token_index + 1;

        foreach my $tok ( @{$rtok} ) {
            last if ( $tok =~ "\n" );
            $rtokens->[ ++$j ] = $tok;
        }
        last;
    }
    return;
}

#########i#############################################################
# Tokenizer guessing routines for ambiguous situations
#######################################################################

sub guess_if_pattern_or_conditional {

    # this routine is called when we have encountered a ? following an
    # unknown bareword, and we must decide if it starts a pattern or not
    # input parameters:
    #   $i - token index of the ? starting possible pattern
    # output parameters:
    #   $is_pattern = 0 if probably not pattern,  =1 if probably a pattern
    #   msg = a warning or diagnostic message
    # USES GLOBAL VARIABLES: $last_nonblank_token

    my ( $i, $rtokens, $rtoken_map, $max_token_index ) = @_;
    my $is_pattern = 0;
    my $msg        = "guessing that ? after $last_nonblank_token starts a ";

    if ( $i >= $max_token_index ) {
        $msg .= "conditional (no end to pattern found on the line)\n";
    }
    else {
        my $ibeg = $i;
        $i = $ibeg + 1;
        my $next_token = $rtokens->[$i];    # first token after ?

        # look for a possible ending ? on this line..
        my $in_quote        = 1;
        my $quote_depth     = 0;
        my $quote_character = '';
        my $quote_pos       = 0;
        my $quoted_string;
        (
            $i, $in_quote, $quote_character, $quote_pos, $quote_depth,
            $quoted_string
          )
          = follow_quoted_string( $ibeg, $in_quote, $rtokens, $quote_character,
            $quote_pos, $quote_depth, $max_token_index );

        if ($in_quote) {

            # we didn't find an ending ? on this line,
            # so we bias towards conditional
            $is_pattern = 0;
            $msg .= "conditional (no ending ? on this line)\n";

            # we found an ending ?, so we bias towards a pattern
        }
        else {

            # Watch out for an ending ? in quotes, like this
            #    my $case_flag = File::Spec->case_tolerant ? '(?i)' : '';
            my $s_quote = 0;
            my $d_quote = 0;
            my $colons  = 0;
            foreach my $ii ( $ibeg + 1 .. $i - 1 ) {
                my $tok = $rtokens->[$ii];
                if ( $tok eq ":" ) { $colons++ }
                if ( $tok eq "'" ) { $s_quote++ }
                if ( $tok eq '"' ) { $d_quote++ }
            }
            if ( $s_quote % 2 || $d_quote % 2 || $colons ) {
                $is_pattern = 0;
                $msg .= "found ending ? but unbalanced quote chars\n";
            }
            elsif ( pattern_expected( $i, $rtokens, $max_token_index ) >= 0 ) {
                $is_pattern = 1;
                $msg .= "pattern (found ending ? and pattern expected)\n";
            }
            else {
                $msg .= "pattern (uncertain, but found ending ?)\n";
            }
        }
    }
    return ( $is_pattern, $msg );
}

my %is_known_constant;
my %is_known_function;

BEGIN {

    # Constants like 'pi' in Trig.pm are common
    my @q = qw(pi pi2 pi4 pip2 pip4);
    @{is_known_constant}{@q} = (1) x scalar(@q);

    # parenless calls of 'ok' are common
    @q = qw( ok );
    @{is_known_function}{@q} = (1) x scalar(@q);
}

sub guess_if_pattern_or_division {

    # this routine is called when we have encountered a / following an
    # unknown bareword, and we must decide if it starts a pattern or is a
    # division
    # input parameters:
    #   $i - token index of the / starting possible pattern
    # output parameters:
    #   $is_pattern = 0 if probably division,  =1 if probably a pattern
    #   msg = a warning or diagnostic message
    # USES GLOBAL VARIABLES: $last_nonblank_token
    my ( $i, $rtokens, $rtoken_map, $max_token_index ) = @_;
    my $is_pattern = 0;
    my $msg        = "guessing that / after $last_nonblank_token starts a ";

    if ( $i >= $max_token_index ) {
        $msg .= "division (no end to pattern found on the line)\n";
    }
    else {
        my $ibeg = $i;
        my $divide_possible =
          is_possible_numerator( $i, $rtokens, $max_token_index );

        if ( $divide_possible < 0 ) {
            $msg        = "pattern (division not possible here)\n";
            $is_pattern = 1;
            goto RETURN;
        }

        $i = $ibeg + 1;
        my $next_token = $rtokens->[$i];    # first token after slash

        # One of the things we can look at is the spacing around the slash.
        # There # are four possible spacings around the first slash:
        #
        #     return pi/two;#/;     -/-
        #     return pi/ two;#/;    -/+
        #     return pi / two;#/;   +/+
        #     return pi /two;#/;    +/-   <-- possible pattern
        #
        # Spacing rule: a space before the slash but not after the slash
        # usually indicates a pattern.  We can use this to break ties.

        my $is_pattern_by_spacing =
          ( $i > 1 && $next_token !~ m/^\s/ && $rtokens->[ $i - 2 ] =~ m/^\s/ );

        # look for a possible ending / on this line..
        my $in_quote        = 1;
        my $quote_depth     = 0;
        my $quote_character = '';
        my $quote_pos       = 0;
        my $quoted_string;
        (
            $i, $in_quote, $quote_character, $quote_pos, $quote_depth,
            $quoted_string
          )
          = follow_quoted_string( $ibeg, $in_quote, $rtokens, $quote_character,
            $quote_pos, $quote_depth, $max_token_index );

        if ($in_quote) {

            # we didn't find an ending / on this line, so we bias towards
            # division
            if ( $divide_possible >= 0 ) {
                $is_pattern = 0;
                $msg .= "division (no ending / on this line)\n";
            }
            else {

                # assuming a multi-line pattern ... this is risky, but division
                # does not seem possible.  If this fails, it would either be due
                # to a syntax error in the code, or the division_expected logic
                # needs to be fixed.
                $msg        = "multi-line pattern (division not possible)\n";
                $is_pattern = 1;
            }
        }

        # we found an ending /, so we bias slightly towards a pattern
        else {

            my $pattern_expected =
              pattern_expected( $i, $rtokens, $max_token_index );

            if ( $pattern_expected >= 0 ) {

                # pattern looks possible...
                if ( $divide_possible >= 0 ) {

                    # Both pattern and divide can work here...

                    # Increase weight of divide if a pure number follows
                    $divide_possible += $next_token =~ /^\d+$/;

                    # Check for known constants in the numerator, like 'pi'
                    if ( $is_known_constant{$last_nonblank_token} ) {
                        $msg .=
"division (pattern works too but saw known constant '$last_nonblank_token')\n";
                        $is_pattern = 0;
                    }

                    # A very common bare word in pattern expressions is 'ok'
                    elsif ( $is_known_function{$last_nonblank_token} ) {
                        $msg .=
"pattern (division works too but saw '$last_nonblank_token')\n";
                        $is_pattern = 1;
                    }

                    # If one rule is more definite, use it
                    elsif ( $divide_possible > $pattern_expected ) {
                        $msg .=
                          "division (more likely based on following tokens)\n";
                        $is_pattern = 0;
                    }

                    # otherwise, use the spacing rule
                    elsif ($is_pattern_by_spacing) {
                        $msg .=
"pattern (guess on spacing, but division possible too)\n";
                        $is_pattern = 1;
                    }
                    else {
                        $msg .=
"division (guess on spacing, but pattern is possible too)\n";
                        $is_pattern = 0;
                    }
                }

                # divide_possible < 0 means divide can not work here
                else {
                    $is_pattern = 1;
                    $msg .= "pattern (division not possible)\n";
                }
            }

            # pattern does not look possible...
            else {

                if ( $divide_possible >= 0 ) {
                    $is_pattern = 0;
                    $msg .= "division (pattern not possible)\n";
                }

                # Neither pattern nor divide look possible...go by spacing
                else {
                    if ($is_pattern_by_spacing) {
                        $msg .= "pattern (guess on spacing)\n";
                        $is_pattern = 1;
                    }
                    else {
                        $msg .= "division (guess on spacing)\n";
                        $is_pattern = 0;
                    }
                }
            }
        }
    }

  RETURN:
    return ( $is_pattern, $msg );
}

# try to resolve here-doc vs. shift by looking ahead for
# non-code or the end token (currently only looks for end token)
# returns 1 if it is probably a here doc, 0 if not
sub guess_if_here_doc {

    # This is how many lines we will search for a target as part of the
    # guessing strategy.  It is a constant because there is probably
    # little reason to change it.
    # USES GLOBAL VARIABLES: $tokenizer_self, $current_package
    # %is_constant,
    my $HERE_DOC_WINDOW = 40;

    my $next_token        = shift;
    my $here_doc_expected = 0;
    my $line;
    my $k   = 0;
    my $msg = "checking <<";

    while ( $line =
        $tokenizer_self->[_line_buffer_object_]->peek_ahead( $k++ ) )
    {
        chomp $line;

        if ( $line =~ /^$next_token$/ ) {
            $msg .= " -- found target $next_token ahead $k lines\n";
            $here_doc_expected = 1;    # got it
            last;
        }
        last if ( $k >= $HERE_DOC_WINDOW );
    }

    unless ($here_doc_expected) {

        if ( !defined($line) ) {
            $here_doc_expected = -1;    # hit eof without seeing target
            $msg .= " -- must be shift; target $next_token not in file\n";

        }
        else {                          # still unsure..taking a wild guess

            if ( !$is_constant{$current_package}{$next_token} ) {
                $here_doc_expected = 1;
                $msg .=
                  " -- guessing it's a here-doc ($next_token not a constant)\n";
            }
            else {
                $msg .=
                  " -- guessing it's a shift ($next_token is a constant)\n";
            }
        }
    }
    write_logfile_entry($msg);
    return $here_doc_expected;
}

#########i#############################################################
# Tokenizer Routines for scanning identifiers and related items
#######################################################################

sub scan_bare_identifier_do {

    # this routine is called to scan a token starting with an alphanumeric
    # variable or package separator, :: or '.
    # USES GLOBAL VARIABLES: $current_package, $last_nonblank_token,
    # $last_nonblank_type,@paren_type, $paren_depth

    my ( $input_line, $i, $tok, $type, $prototype, $rtoken_map,
        $max_token_index )
      = @_;
    my $i_begin = $i;
    my $package = undef;

    my $i_beg = $i;

    # we have to back up one pretoken at a :: since each : is one pretoken
    if ( $tok eq '::' ) { $i_beg-- }
    if ( $tok eq '->' ) { $i_beg-- }
    my $pos_beg = $rtoken_map->[$i_beg];
    pos($input_line) = $pos_beg;

    #  Examples:
    #   A::B::C
    #   A::
    #   ::A
    #   A'B
    if ( $input_line =~ m/\G\s*((?:\w*(?:'|::)))*(?:(?:->)?(\w+))?/gc ) {

        my $pos  = pos($input_line);
        my $numc = $pos - $pos_beg;
        $tok = substr( $input_line, $pos_beg, $numc );

        # type 'w' includes anything without leading type info
        # ($,%,@,*) including something like abc::def::ghi
        $type = 'w';

        my $sub_name = "";
        if ( defined($2) ) { $sub_name = $2; }
        if ( defined($1) ) {
            $package = $1;

            # patch: don't allow isolated package name which just ends
            # in the old style package separator (single quote).  Example:
            #   use CGI':all';
            if ( !($sub_name) && substr( $package, -1, 1 ) eq '\'' ) {
                $pos--;
            }

            $package =~ s/\'/::/g;
            if ( $package =~ /^\:/ ) { $package = 'main' . $package }
            $package =~ s/::$//;
        }
        else {
            $package = $current_package;

            # patched for c043, part 1: keyword does not follow '->'
            if ( $is_keyword{$tok} && $last_nonblank_type ne '->' ) {
                $type = 'k';
            }
        }

        # if it is a bareword..  patched for c043, part 2: not following '->'
        if ( $type eq 'w' && $last_nonblank_type ne '->' ) {

            # check for v-string with leading 'v' type character
            # (This seems to have precedence over filehandle, type 'Y')
            if ( $tok =~ /^v\d[_\d]*$/ ) {

                # we only have the first part - something like 'v101' -
                # look for more
                if ( $input_line =~ m/\G(\.\d[_\d]*)+/gc ) {
                    $pos  = pos($input_line);
                    $numc = $pos - $pos_beg;
                    $tok  = substr( $input_line, $pos_beg, $numc );
                }
                $type = 'v';

                # warn if this version can't handle v-strings
                report_v_string($tok);
            }

            elsif ( $is_constant{$package}{$sub_name} ) {
                $type = 'C';
            }

            # bareword after sort has implied empty prototype; for example:
            # @sorted = sort numerically ( 53, 29, 11, 32, 7 );
            # This has priority over whatever the user has specified.
            elsif ($last_nonblank_token eq 'sort'
                && $last_nonblank_type eq 'k' )
            {
                $type = 'Z';
            }

            # Note: strangely, perl does not seem to really let you create
            # functions which act like eval and do, in the sense that eval
            # and do may have operators following the final }, but any operators
            # that you create with prototype (&) apparently do not allow
            # trailing operators, only terms.  This seems strange.
            # If this ever changes, here is the update
            # to make perltidy behave accordingly:

            # elsif ( $is_block_function{$package}{$tok} ) {
            #    $tok='eval'; # patch to do braces like eval  - doesn't work
            #    $type = 'k';
            #}
            # FIXME: This could become a separate type to allow for different
            # future behavior:
            elsif ( $is_block_function{$package}{$sub_name} ) {
                $type = 'G';
            }
            elsif ( $is_block_list_function{$package}{$sub_name} ) {
                $type = 'G';
            }
            elsif ( $is_user_function{$package}{$sub_name} ) {
                $type      = 'U';
                $prototype = $user_function_prototype{$package}{$sub_name};
            }

            # check for indirect object
            elsif (

                # added 2001-03-27: must not be followed immediately by '('
                # see fhandle.t
                ( $input_line !~ m/\G\(/gc )

                # and
                && (

                    # preceded by keyword like 'print', 'printf' and friends
                    $is_indirect_object_taker{$last_nonblank_token}

                    # or preceded by something like 'print(' or 'printf('
                    || (
                        ( $last_nonblank_token eq '(' )
                        && $is_indirect_object_taker{ $paren_type[$paren_depth]
                        }

                    )
                )
              )
            {

                # may not be indirect object unless followed by a space;
                # updated 2021-01-16 to consider newline to be a space.
                # updated for case b990 to look for either ';' or space
                if ( pos($input_line) == length($input_line)
                    || $input_line =~ m/\G[;\s]/gc )
                {
                    $type = 'Y';

                    # Abandon Hope ...
                    # Perl's indirect object notation is a very bad
                    # thing and can cause subtle bugs, especially for
                    # beginning programmers.  And I haven't even been
                    # able to figure out a sane warning scheme which
                    # doesn't get in the way of good scripts.

                    # Complain if a filehandle has any lower case
                    # letters.  This is suggested good practice.
                    # Use 'sub_name' because something like
                    # main::MYHANDLE is ok for filehandle
                    if ( $sub_name =~ /[a-z]/ ) {

                        # could be bug caused by older perltidy if
                        # followed by '('
                        if ( $input_line =~ m/\G\s*\(/gc ) {
                            complain(
"Caution: unknown word '$tok' in indirect object slot\n"
                            );
                        }
                    }
                }

                # bareword not followed by a space -- may not be filehandle
                # (may be function call defined in a 'use' statement)
                else {
                    $type = 'Z';
                }
            }
        }

        # Now we must convert back from character position
        # to pre_token index.
        # I don't think an error flag can occur here ..but who knows
        my $error;
        ( $i, $error ) =
          inverse_pretoken_map( $i, $pos, $rtoken_map, $max_token_index );
        if ($error) {
            warning("scan_bare_identifier: Possibly invalid tokenization\n");
        }
    }

    # no match but line not blank - could be syntax error
    # perl will take '::' alone without complaint
    else {
        $type = 'w';

        # change this warning to log message if it becomes annoying
        warning("didn't find identifier after leading ::\n");
    }
    return ( $i, $tok, $type, $prototype );
}

sub scan_id_do {

# This is the new scanner and will eventually replace scan_identifier.
# Only type 'sub' and 'package' are implemented.
# Token types $ * % @ & -> are not yet implemented.
#
# Scan identifier following a type token.
# The type of call depends on $id_scan_state: $id_scan_state = ''
# for starting call, in which case $tok must be the token defining
# the type.
#
# If the type token is the last nonblank token on the line, a value
# of $id_scan_state = $tok is returned, indicating that further
# calls must be made to get the identifier.  If the type token is
# not the last nonblank token on the line, the identifier is
# scanned and handled and a value of '' is returned.
# USES GLOBAL VARIABLES: $current_package, $last_nonblank_token, $in_attribute_list,
# $statement_type, $tokenizer_self

    my ( $input_line, $i, $tok, $rtokens, $rtoken_map, $id_scan_state,
        $max_token_index )
      = @_;
    use constant DEBUG_NSCAN => 0;
    my $type = '';
    my ( $i_beg, $pos_beg );

    #print "NSCAN:entering i=$i, tok=$tok, type=$type, state=$id_scan_state\n";
    #my ($a,$b,$c) = caller;
    #print "NSCAN: scan_id called with tok=$tok $a $b $c\n";

    # on re-entry, start scanning at first token on the line
    if ($id_scan_state) {
        $i_beg = $i;
        $type  = '';
    }

    # on initial entry, start scanning just after type token
    else {
        $i_beg         = $i + 1;
        $id_scan_state = $tok;
        $type          = 't';
    }

    # find $i_beg = index of next nonblank token,
    # and handle empty lines
    my $blank_line          = 0;
    my $next_nonblank_token = $rtokens->[$i_beg];
    if ( $i_beg > $max_token_index ) {
        $blank_line = 1;
    }
    else {

        # only a '#' immediately after a '$' is not a comment
        if ( $next_nonblank_token eq '#' ) {
            unless ( $tok eq '$' ) {
                $blank_line = 1;
            }
        }

        if ( $next_nonblank_token =~ /^\s/ ) {
            ( $next_nonblank_token, $i_beg ) =
              find_next_nonblank_token_on_this_line( $i_beg, $rtokens,
                $max_token_index );
            if ( $next_nonblank_token =~ /(^#|^\s*$)/ ) {
                $blank_line = 1;
            }
        }
    }

    # handle non-blank line; identifier, if any, must follow
    unless ($blank_line) {

        if ( $is_sub{$id_scan_state} ) {
            ( $i, $tok, $type, $id_scan_state ) = do_scan_sub(
                {
                    input_line      => $input_line,
                    i               => $i,
                    i_beg           => $i_beg,
                    tok             => $tok,
                    type            => $type,
                    rtokens         => $rtokens,
                    rtoken_map      => $rtoken_map,
                    id_scan_state   => $id_scan_state,
                    max_token_index => $max_token_index
                }
            );
        }

        elsif ( $is_package{$id_scan_state} ) {
            ( $i, $tok, $type ) =
              do_scan_package( $input_line, $i, $i_beg, $tok, $type, $rtokens,
                $rtoken_map, $max_token_index );
            $id_scan_state = '';
        }

        else {
            warning("invalid token in scan_id: $tok\n");
            $id_scan_state = '';
        }
    }

    if ( $id_scan_state && ( !defined($type) || !$type ) ) {

        # shouldn't happen:
        if (DEVEL_MODE) {
            Fault(<<EOM);
Program bug in scan_id: undefined type but scan_state=$id_scan_state
EOM
        }
        warning(
"Possible program bug in sub scan_id: undefined type but scan_state=$id_scan_state\n"
        );
        report_definite_bug();
    }

    DEBUG_NSCAN && do {
        print STDOUT
          "NSCAN: returns i=$i, tok=$tok, type=$type, state=$id_scan_state\n";
    };
    return ( $i, $tok, $type, $id_scan_state );
}

sub check_prototype {
    my ( $proto, $package, $subname ) = @_;
    return unless ( defined($package) && defined($subname) );
    if ( defined($proto) ) {
        $proto =~ s/^\s*\(\s*//;
        $proto =~ s/\s*\)$//;
        if ($proto) {
            $is_user_function{$package}{$subname}        = 1;
            $user_function_prototype{$package}{$subname} = "($proto)";

            # prototypes containing '&' must be treated specially..
            if ( $proto =~ /\&/ ) {

                # right curly braces of prototypes ending in
                # '&' may be followed by an operator
                if ( $proto =~ /\&$/ ) {
                    $is_block_function{$package}{$subname} = 1;
                }

                # right curly braces of prototypes NOT ending in
                # '&' may NOT be followed by an operator
                elsif ( $proto !~ /\&$/ ) {
                    $is_block_list_function{$package}{$subname} = 1;
                }
            }
        }
        else {
            $is_constant{$package}{$subname} = 1;
        }
    }
    else {
        $is_user_function{$package}{$subname} = 1;
    }
    return;
}

sub do_scan_package {

    # do_scan_package parses a package name
    # it is called with $i_beg equal to the index of the first nonblank
    # token following a 'package' token.
    # USES GLOBAL VARIABLES: $current_package,

    # package NAMESPACE
    # package NAMESPACE VERSION
    # package NAMESPACE BLOCK
    # package NAMESPACE VERSION BLOCK
    #
    # If VERSION is provided, package sets the $VERSION variable in the given
    # namespace to a version object with the VERSION provided. VERSION must be
    # a "strict" style version number as defined by the version module: a
    # positive decimal number (integer or decimal-fraction) without
    # exponentiation or else a dotted-decimal v-string with a leading 'v'
    # character and at least three components.
    # reference http://perldoc.perl.org/functions/package.html

    my ( $input_line, $i, $i_beg, $tok, $type, $rtokens, $rtoken_map,
        $max_token_index )
      = @_;
    my $package = undef;
    my $pos_beg = $rtoken_map->[$i_beg];
    pos($input_line) = $pos_beg;

    # handle non-blank line; package name, if any, must follow
    if ( $input_line =~ m/\G\s*((?:\w*(?:'|::))*\w*)/gc ) {
        $package = $1;
        $package = ( defined($1) && $1 ) ? $1 : 'main';
        $package =~ s/\'/::/g;
        if ( $package =~ /^\:/ ) { $package = 'main' . $package }
        $package =~ s/::$//;
        my $pos  = pos($input_line);
        my $numc = $pos - $pos_beg;
        $tok  = 'package ' . substr( $input_line, $pos_beg, $numc );
        $type = 'i';

        # Now we must convert back from character position
        # to pre_token index.
        # I don't think an error flag can occur here ..but ?
        my $error;
        ( $i, $error ) =
          inverse_pretoken_map( $i, $pos, $rtoken_map, $max_token_index );
        if ($error) { warning("Possibly invalid package\n") }
        $current_package = $package;

        # we should now have package NAMESPACE
        # now expecting VERSION, BLOCK, or ; to follow ...
        # package NAMESPACE VERSION
        # package NAMESPACE BLOCK
        # package NAMESPACE VERSION BLOCK
        my ( $next_nonblank_token, $i_next ) =
          find_next_nonblank_token( $i, $rtokens, $max_token_index );

        # check that something recognizable follows, but do not parse.
        # A VERSION number will be parsed later as a number or v-string in the
        # normal way.  What is important is to set the statement type if
        # everything looks okay so that the operator_expected() routine
        # knows that the number is in a package statement.
        # Examples of valid primitive tokens that might follow are:
        #  1235  . ; { } v3  v
        # FIX: added a '#' since a side comment may also follow
        if ( $next_nonblank_token =~ /^([v\.\d;\{\}\#])|v\d|\d+$/ ) {
            $statement_type = $tok;
        }
        else {
            warning(
                "Unexpected '$next_nonblank_token' after package name '$tok'\n"
            );
        }
    }

    # no match but line not blank --
    # could be a label with name package, like package:  , for example.
    else {
        $type = 'k';
    }

    return ( $i, $tok, $type );
}

my %is_special_variable_char;

BEGIN {

    # These are the only characters which can (currently) form special
    # variables, like $^W: (issue c066).
    my @q =
      qw{ ? A B C D E F G H I J K L M N O P Q R S T U V W X Y Z [ \ ] ^ _ };
    @{is_special_variable_char}{@q} = (1) x scalar(@q);
}

sub scan_identifier_do {

    # This routine assembles tokens into identifiers.  It maintains a
    # scan state, id_scan_state.  It updates id_scan_state based upon
    # current id_scan_state and token, and returns an updated
    # id_scan_state and the next index after the identifier.

    # USES GLOBAL VARIABLES: $context, $last_nonblank_token,
    # $last_nonblank_type

    my ( $i, $id_scan_state, $identifier, $rtokens, $max_token_index,
        $expecting, $container_type )
      = @_;
    use constant DEBUG_SCAN_ID => 0;
    my $i_begin   = $i;
    my $type      = '';
    my $tok_begin = $rtokens->[$i_begin];
    if ( $tok_begin eq ':' ) { $tok_begin = '::' }
    my $id_scan_state_begin = $id_scan_state;
    my $identifier_begin    = $identifier;
    my $tok                 = $tok_begin;
    my $message             = "";
    my $tok_is_blank;    # a flag to speed things up

    my $in_prototype_or_signature =
      $container_type && $container_type =~ /^sub\b/;

    # these flags will be used to help figure out the type:
    my $saw_alpha;
    my $saw_type;

    # allow old package separator (') except in 'use' statement
    my $allow_tick = ( $last_nonblank_token ne 'use' );

    #########################################################
    # get started by defining a type and a state if necessary
    #########################################################

    if ( !$id_scan_state ) {
        $context = UNKNOWN_CONTEXT;

        # fixup for digraph
        if ( $tok eq '>' ) {
            $tok       = '->';
            $tok_begin = $tok;
        }
        $identifier = $tok;

        if ( $tok eq '$' || $tok eq '*' ) {
            $id_scan_state = '$';
            $context       = SCALAR_CONTEXT;
        }
        elsif ( $tok eq '%' || $tok eq '@' ) {
            $id_scan_state = '$';
            $context       = LIST_CONTEXT;
        }
        elsif ( $tok eq '&' ) {
            $id_scan_state = '&';
        }
        elsif ( $tok eq 'sub' or $tok eq 'package' ) {
            $saw_alpha     = 0;     # 'sub' is considered type info here
            $id_scan_state = '$';
            $identifier .= ' ';     # need a space to separate sub from sub name
        }
        elsif ( $tok eq '::' ) {
            $id_scan_state = 'A';
        }
        elsif ( $tok =~ /^\w/ ) {
            $id_scan_state = ':';
            $saw_alpha     = 1;
        }
        elsif ( $tok eq '->' ) {
            $id_scan_state = '$';
        }
        else {

            # shouldn't happen: bad call parameter
            my $msg =
"Program bug detected: scan_identifier received bad starting token = '$tok'\n";
            if (DEVEL_MODE) { Fault($msg) }
            if ( !$tokenizer_self->[_in_error_] ) {
                warning($msg);
                $tokenizer_self->[_in_error_] = 1;
            }
            $id_scan_state = '';
            goto RETURN;
        }
        $saw_type = !$saw_alpha;
    }
    else {
        $i--;
        $saw_alpha = ( $tok =~ /^\w/ );
        $saw_type  = ( $tok =~ /([\$\%\@\*\&])/ );
    }

    ###############################
    # loop to gather the identifier
    ###############################

    my $i_save = $i;

    while ( $i < $max_token_index ) {
        my $last_tok_is_blank = $tok_is_blank;
        if   ($tok_is_blank) { $tok_is_blank = undef }
        else                 { $i_save       = $i }

        $tok = $rtokens->[ ++$i ];

        # patch to make digraph :: if necessary
        if ( ( $tok eq ':' ) && ( $rtokens->[ $i + 1 ] eq ':' ) ) {
            $tok = '::';
            $i++;
        }

        ########################
        # Starting variable name
        ########################

        if ( $id_scan_state eq '$' ) {

            if ( $tok eq '$' ) {

                $identifier .= $tok;

                # we've got a punctuation variable if end of line (punct.t)
                if ( $i == $max_token_index ) {
                    $type          = 'i';
                    $id_scan_state = '';
                    last;
                }
            }
            elsif ( $tok =~ /^\w/ ) {    # alphanumeric ..
                $saw_alpha     = 1;
                $id_scan_state = ':';    # now need ::
                $identifier .= $tok;
            }
            elsif ( $tok eq '::' ) {
                $id_scan_state = 'A';
                $identifier .= $tok;
            }

            # POSTDEFREF ->@ ->% ->& ->*
            elsif ( ( $tok =~ /^[\@\%\&\*]$/ ) && $identifier =~ /\-\>$/ ) {
                $identifier .= $tok;
            }
            elsif ( $tok eq "'" && $allow_tick ) {    # alphanumeric ..
                $saw_alpha     = 1;
                $id_scan_state = ':';                 # now need ::
                $identifier .= $tok;

                # Perl will accept leading digits in identifiers,
                # although they may not always produce useful results.
                # Something like $main::0 is ok.  But this also works:
                #
                #  sub howdy::123::bubba{ print "bubba $54321!\n" }
                #  howdy::123::bubba();
                #
            }
            elsif ( $tok eq '#' ) {

                # side comment or identifier?
                if (

                    # A '#' starts a comment if it follows a space. For example,
                    # the following is equivalent to $ans=40.
                    #   my $ #
                    #     ans = 40;
                    !$last_tok_is_blank

                    # a # inside a prototype or signature can only start a
                    # comment
                    && !$in_prototype_or_signature

                    # these are valid punctuation vars: *# %# @# $#
                    # May also be '$#array' or POSTDEFREF ->$#
                    && ( $identifier =~ /^[\%\@\$\*]$/ || $identifier =~ /\$$/ )

                  )
                {
                    $identifier .= $tok;    # keep same state, a $ could follow
                }
                else {

                    # otherwise it is a side comment
                    if    ( $identifier eq '->' )   { }
                    elsif ( $id_scan_state eq '$' ) { $type = 't' }
                    else                            { $type = 'i' }
                    $i             = $i_save;
                    $id_scan_state = '';
                    last;
                }
            }

            elsif ( $tok eq '{' ) {

                # check for something like ${#} or ${�}
                if (
                    (
                           $identifier eq '$'
                        || $identifier eq '@'
                        || $identifier eq '$#'
                    )
                    && $i + 2 <= $max_token_index
                    && $rtokens->[ $i + 2 ] eq '}'
                    && $rtokens->[ $i + 1 ] !~ /[\s\w]/
                  )
                {
                    my $next2 = $rtokens->[ $i + 2 ];
                    my $next1 = $rtokens->[ $i + 1 ];
                    $identifier .= $tok . $next1 . $next2;
                    $i += 2;
                    $id_scan_state = '';
                    last;
                }

                # skip something like ${xxx} or ->{
                $id_scan_state = '';

                # if this is the first token of a line, any tokens for this
                # identifier have already been accumulated
                if ( $identifier eq '$' || $i == 0 ) { $identifier = ''; }
                $i = $i_save;
                last;
            }

            # space ok after leading $ % * & @
            elsif ( $tok =~ /^\s*$/ ) {

                $tok_is_blank = 1;

                if ( $identifier =~ /^[\$\%\*\&\@]/ ) {

                    if ( length($identifier) > 1 ) {
                        $id_scan_state = '';
                        $i             = $i_save;
                        $type          = 'i';    # probably punctuation variable
                        last;
                    }
                    else {

                        # spaces after $'s are common, and space after @
                        # is harmless, so only complain about space
                        # after other type characters. Space after $ and
                        # @ will be removed in formatting.  Report space
                        # after % and * because they might indicate a
                        # parsing error.  In other words '% ' might be a
                        # modulo operator.  Delete this warning if it
                        # gets annoying.
                        if ( $identifier !~ /^[\@\$]$/ ) {
                            $message =
                              "Space in identifier, following $identifier\n";
                        }
                    }
                }

                # else:
                # space after '->' is ok
            }
            elsif ( $tok eq '^' ) {

                # check for some special variables like $^ $^W
                if ( $identifier =~ /^[\$\*\@\%]$/ ) {
                    $identifier .= $tok;
                    $type = 'i';

                    # There may be one more character, not a space, after the ^
                    my $next1 = $rtokens->[ $i + 1 ];
                    my $chr   = substr( $next1, 0, 1 );
                    if ( $is_special_variable_char{$chr} ) {

                        # It is something like $^W
                        # Test case (c066) : $^Oeq'linux'
                        $i++;
                        $identifier .= $next1;

                        # If pretoken $next1 is more than one character long,
                        # set a flag indicating that it needs to be split.
                        $id_scan_state = ( length($next1) > 1 ) ? '^' : "";
                        last;
                    }
                    else {

                        # it is just $^
                        # Simple test case (c065): '$aa=$^if($bb)';
                        $id_scan_state = "";
                        last;
                    }
                }
                else {
                    $id_scan_state = '';
                    $i             = $i_save;
                    last;    # c106
                }
            }
            else {           # something else

                if ( $in_prototype_or_signature && $tok =~ /^[\),=#]/ ) {

                    # We might be in an extrusion of
                    #     sub foo2 ( $first, $, $third ) {
                    # looking at a line starting with a comma, like
                    #   $
                    #   ,
                    # in this case the comma ends the signature variable
                    # '$' which will have been previously marked type 't'
                    # rather than 'i'.
                    if ( $i == $i_begin ) {
                        $identifier = "";
                        $type       = "";
                    }

                    # at a # we have to mark as type 't' because more may
                    # follow, otherwise, in a signature we can let '$' be an
                    # identifier here for better formatting.
                    # See 'mangle4.in' for a test case.
                    else {
                        $type = 'i';
                        if ( $id_scan_state eq '$' && $tok eq '#' ) {
                            $type = 't';
                        }
                        $i = $i_save;
                    }
                    $id_scan_state = '';
                    last;
                }

                # check for various punctuation variables
                if ( $identifier =~ /^[\$\*\@\%]$/ ) {
                    $identifier .= $tok;
                }

                # POSTDEFREF: Postfix reference ->$* ->%*  ->@* ->** ->&* ->$#*
                elsif ($tok eq '*'
                    && $identifier =~ /\-\>([\@\%\$\*\&]|\$\#)$/ )
                {
                    $identifier .= $tok;
                }

                elsif ( $identifier eq '$#' ) {

                    if ( $tok eq '{' ) { $type = 'i'; $i = $i_save }

                    # perl seems to allow just these: $#: $#- $#+
                    elsif ( $tok =~ /^[\:\-\+]$/ ) {
                        $type = 'i';
                        $identifier .= $tok;
                    }
                    else {
                        $i = $i_save;
                        write_logfile_entry( 'Use of $# is deprecated' . "\n" );
                    }
                }
                elsif ( $identifier eq '$$' ) {

                    # perl does not allow references to punctuation
                    # variables without braces.  For example, this
                    # won't work:
                    #  $:=\4;
                    #  $a = $$:;
                    # You would have to use
                    #  $a = ${$:};

                    # '$$' alone is punctuation variable for PID
                    $i = $i_save;
                    if   ( $tok eq '{' ) { $type = 't' }
                    else                 { $type = 'i' }
                }
                elsif ( $identifier eq '->' ) {
                    $i = $i_save;
                }
                else {
                    $i = $i_save;
                    if ( length($identifier) == 1 ) { $identifier = ''; }
                }
                $id_scan_state = '';
                last;
            }
        }

        ###################################
        # looking for alphanumeric after ::
        ###################################

        elsif ( $id_scan_state eq 'A' ) {

            $tok_is_blank = $tok =~ /^\s*$/;

            if ( $tok =~ /^\w/ ) {    # found it
                $identifier .= $tok;
                $id_scan_state = ':';    # now need ::
                $saw_alpha     = 1;
            }
            elsif ( $tok eq "'" && $allow_tick ) {
                $identifier .= $tok;
                $id_scan_state = ':';    # now need ::
                $saw_alpha     = 1;
            }
            elsif ( $tok_is_blank && $identifier =~ /^sub / ) {
                $id_scan_state = '(';
                $identifier .= $tok;
            }
            elsif ( $tok eq '(' && $identifier =~ /^sub / ) {
                $id_scan_state = ')';
                $identifier .= $tok;
            }
            else {
                $id_scan_state = '';
                $i             = $i_save;
                last;
            }
        }

        ###################################
        # looking for :: after alphanumeric
        ###################################

        elsif ( $id_scan_state eq ':' ) {    # looking for :: after alpha

            $tok_is_blank = $tok =~ /^\s*$/;

            if ( $tok eq '::' ) {            # got it
                $identifier .= $tok;
                $id_scan_state = 'A';        # now require alpha
            }
            elsif ( $tok =~ /^\w/ ) {        # more alphanumeric is ok here
                $identifier .= $tok;
                $id_scan_state = ':';        # now need ::
                $saw_alpha     = 1;
            }
            elsif ( $tok eq "'" && $allow_tick ) {    # tick

                if ( $is_keyword{$identifier} ) {
                    $id_scan_state = '';              # that's all
                    $i             = $i_save;
                }
                else {
                    $identifier .= $tok;
                }
            }
            elsif ( $tok_is_blank && $identifier =~ /^sub / ) {
                $id_scan_state = '(';
                $identifier .= $tok;
            }
            elsif ( $tok eq '(' && $identifier =~ /^sub / ) {
                $id_scan_state = ')';
                $identifier .= $tok;
            }
            else {
                $id_scan_state = '';        # that's all
                $i             = $i_save;
                last;
            }
        }

        ##############################
        # looking for '(' of prototype
        ##############################

        elsif ( $id_scan_state eq '(' ) {

            if ( $tok eq '(' ) {    # got it
                $identifier .= $tok;
                $id_scan_state = ')';    # now find the end of it
            }
            elsif ( $tok =~ /^\s*$/ ) {    # blank - keep going
                $identifier .= $tok;
                $tok_is_blank = 1;
            }
            else {
                $id_scan_state = '';        # that's all - no prototype
                $i             = $i_save;
                last;
            }
        }

        ##############################
        # looking for ')' of prototype
        ##############################

        elsif ( $id_scan_state eq ')' ) {

            $tok_is_blank = $tok =~ /^\s*$/;

            if ( $tok eq ')' ) {    # got it
                $identifier .= $tok;
                $id_scan_state = '';    # all done
                last;
            }
            elsif ( $tok =~ /^[\s\$\%\\\*\@\&\;]/ ) {
                $identifier .= $tok;
            }
            else {    # probable error in script, but keep going
                warning("Unexpected '$tok' while seeking end of prototype\n");
                $identifier .= $tok;
            }
        }

        ###################
        # Starting sub call
        ###################

        elsif ( $id_scan_state eq '&' ) {

            if ( $tok =~ /^[\$\w]/ ) {    # alphanumeric ..
                $id_scan_state = ':';     # now need ::
                $saw_alpha     = 1;
                $identifier .= $tok;
            }
            elsif ( $tok eq "'" && $allow_tick ) {    # alphanumeric ..
                $id_scan_state = ':';                 # now need ::
                $saw_alpha     = 1;
                $identifier .= $tok;
            }
            elsif ( $tok =~ /^\s*$/ ) {               # allow space
                $tok_is_blank = 1;
            }
            elsif ( $tok eq '::' ) {                  # leading ::
                $id_scan_state = 'A';                 # accept alpha next
                $identifier .= $tok;
            }
            elsif ( $tok eq '{' ) {
                if ( $identifier eq '&' || $i == 0 ) { $identifier = ''; }
                $i             = $i_save;
                $id_scan_state = '';
                last;
            }
            elsif ( $tok eq '^' ) {
                if ( $identifier eq '&' ) {

                    # Special variable (c066)
                    $identifier .= $tok;
                    $type = '&';

                    # There may be one more character, not a space, after the ^
                    my $next1 = $rtokens->[ $i + 1 ];
                    my $chr   = substr( $next1, 0, 1 );
                    if ( $is_special_variable_char{$chr} ) {

                        # It is something like &^O
                        $i++;
                        $identifier .= $next1;

                        # If pretoken $next1 is more than one character long,
                        # set a flag indicating that it needs to be split.
                        $id_scan_state = ( length($next1) > 1 ) ? '^' : "";
                    }
                    else {

                        # it is &^
                        $id_scan_state = "";
                    }
                    last;
                }
                else {
                    $identifier = '';
                    $i          = $i_save;
                }
                last;
            }
            else {

                # punctuation variable?
                # testfile: cunningham4.pl
                #
                # We have to be careful here.  If we are in an unknown state,
                # we will reject the punctuation variable.  In the following
                # example the '&' is a binary operator but we are in an unknown
                # state because there is no sigil on 'Prima', so we don't
                # know what it is.  But it is a bad guess that
                # '&~' is a function variable.
                # $self->{text}->{colorMap}->[
                #   Prima::PodView::COLOR_CODE_FOREGROUND
                #   & ~tb::COLOR_INDEX ] =
                #   $sec->{ColorCode}

                # Fix for case c033: a '#' here starts a side comment
                if ( $identifier eq '&' && $expecting && $tok ne '#' ) {
                    $identifier .= $tok;
                }
                else {
                    $identifier = '';
                    $i          = $i_save;
                    $type       = '&';
                }
                $id_scan_state = '';
                last;
            }
        }

        ######################
        # unknown state - quit
        ######################

        else {    # can get here due to error in initialization
            $id_scan_state = '';
            $i             = $i_save;
            last;
        }
    } ## end of main loop

    if ( $id_scan_state eq ')' ) {
        warning("Hit end of line while seeking ) to end prototype\n");
    }

    # once we enter the actual identifier, it may not extend beyond
    # the end of the current line
    if ( $id_scan_state =~ /^[A\:\(\)]/ ) {
        $id_scan_state = '';
    }

    # Patch: the deprecated variable $# does not combine with anything on the
    # next line.
    if ( $identifier eq '$#' ) { $id_scan_state = '' }

    if ( $i < 0 ) { $i = 0 }

    # Be sure a token type is defined
    if ( !$type ) {

        if ($saw_type) {

            if ($saw_alpha) {

                # The type without the -> should be the same as with the -> so
                # that if they get separated we get the same bond strengths,
                # etc.  See b1234
                if (   $identifier =~ /^->/
                    && $last_nonblank_type eq 'w'
                    && substr( $identifier, 2, 1 ) =~ /^\w/ )
                {
                    $type = 'w';
                }
                else { $type = 'i' }
            }
            elsif ( $identifier eq '->' ) {
                $type = '->';
            }
            elsif (
                ( length($identifier) > 1 )

                # In something like '@$=' we have an identifier '@$'
                # In something like '$${' we have type '$$' (and only
                # part of an identifier)
                && !( $identifier =~ /\$$/ && $tok eq '{' )
                && ( $identifier !~ /^(sub |package )$/ )
              )
            {
                $type = 'i';
            }
            else { $type = 't' }
        }
        elsif ($saw_alpha) {

            # type 'w' includes anything without leading type info
            # ($,%,@,*) including something like abc::def::ghi
            $type = 'w';
        }
        else {
            $type = '';
        }    # this can happen on a restart
    }

    # See if we formed an identifier...
    if ($identifier) {
        $tok = $identifier;
        if ($message) { write_logfile_entry($message) }
    }

    # did not find an identifier, back  up
    else {
        $tok = $tok_begin;
        $i   = $i_begin;
    }

  RETURN:

    DEBUG_SCAN_ID && do {
        my ( $a, $b, $c ) = caller;
        print STDOUT
"SCANID: called from $a $b $c with tok, i, state, identifier =$tok_begin, $i_begin, $id_scan_state_begin, $identifier_begin\n";
        print STDOUT
"SCANID: returned with tok, i, state, identifier =$tok, $i, $id_scan_state, $identifier\n";
    };
    return ( $i, $tok, $type, $id_scan_state, $identifier );
}

{    ## closure for sub do_scan_sub

    my %warn_if_lexical;

    BEGIN {

        # lexical subs with these names can cause parsing errors in this version
        my @q = qw( m q qq qr qw qx s tr y );
        @{warn_if_lexical}{@q} = (1) x scalar(@q);
    }

    # saved package and subnames in case prototype is on separate line
    my ( $package_saved, $subname_saved );

    # initialize subname each time a new 'sub' keyword is encountered
    sub initialize_subname {
        $package_saved = "";
        $subname_saved = "";
        return;
    }

    use constant {
        SUB_CALL       => 1,
        PAREN_CALL     => 2,
        PROTOTYPE_CALL => 3,
    };

    sub do_scan_sub {

        # do_scan_sub parses a sub name and prototype.

        # At present there are three basic CALL TYPES which are
        # distinguished by the starting value of '$tok':
        # 1. $tok='sub', id_scan_state='sub'
        #    it is called with $i_beg equal to the index of the first nonblank
        #    token following a 'sub' token.
        # 2. $tok='(', id_scan_state='sub',
        #    it is called with $i_beg equal to the index of a '(' which may
        #    start a prototype.
        # 3. $tok='prototype', id_scan_state='prototype'
        #    it is called with $i_beg equal to the index of a '(' which is
        #    preceded by ': prototype' and has $id_scan_state eq 'prototype'

        # Examples:

        # A single type 1 call will get both the sub and prototype
        #   sub foo1 ( $$ ) { }
        #   ^

        # The subname will be obtained with a 'sub' call
        # The prototype on line 2 will be obtained with a '(' call
        #   sub foo1
        #   ^                    <---call type 1
        #     ( $$ ) { }
        #     ^                  <---call type 2

        # The subname will be obtained with a 'sub' call
        # The prototype will be obtained with a 'prototype' call
        #   sub foo1 ( $x, $y ) : prototype ( $$ ) { }
        #   ^ <---type 1                    ^ <---type 3

        # TODO: add future error checks to be sure we have a valid
        # sub name.  For example, 'sub &doit' is wrong.  Also, be sure
        # a name is given if and only if a non-anonymous sub is
        # appropriate.
        # USES GLOBAL VARS: $current_package, $last_nonblank_token,
        # $in_attribute_list, %saw_function_definition,
        # $statement_type

        my ($rinput_hash) = @_;

        my $input_line      = $rinput_hash->{input_line};
        my $i               = $rinput_hash->{i};
        my $i_beg           = $rinput_hash->{i_beg};
        my $tok             = $rinput_hash->{tok};
        my $type            = $rinput_hash->{type};
        my $rtokens         = $rinput_hash->{rtokens};
        my $rtoken_map      = $rinput_hash->{rtoken_map};
        my $id_scan_state   = $rinput_hash->{id_scan_state};
        my $max_token_index = $rinput_hash->{max_token_index};

        my $i_entry = $i;

        # Determine the CALL TYPE
        # 1=sub
        # 2=(
        # 3=prototype
        my $call_type =
            $tok eq 'prototype' ? PROTOTYPE_CALL
          : $tok eq '('         ? PAREN_CALL
          :                       SUB_CALL;

        $id_scan_state = "";    # normally we get everything in one call
        my $subname = $subname_saved;
        my $package = $package_saved;
        my $proto   = undef;
        my $attrs   = undef;
        my $match;

        my $pos_beg = $rtoken_map->[$i_beg];
        pos($input_line) = $pos_beg;

        # Look for the sub NAME if this is a SUB call
        if (
               $call_type == SUB_CALL
            && $input_line =~ m/\G\s*
        ((?:\w*(?:'|::))*)  # package - something that ends in :: or '
        (\w+)               # NAME    - required
        /gcx
          )
        {
            $match   = 1;
            $subname = $2;

            my $is_lexical_sub =
              $last_nonblank_type eq 'k' && $last_nonblank_token eq 'my';
            if ( $is_lexical_sub && $1 ) {
                warning("'my' sub $subname cannot be in package '$1'\n");
                $is_lexical_sub = 0;
            }

            if ($is_lexical_sub) {

                # lexical subs use the block sequence number as a package name
                my $seqno =
                  $current_sequence_number[BRACE][ $current_depth[BRACE] ];
                $seqno   = 1 unless ( defined($seqno) );
                $package = $seqno;
                if ( $warn_if_lexical{$subname} ) {
                    warning(
"'my' sub '$subname' matches a builtin name and may not be handled correctly in this perltidy version.\n"
                    );
                }
            }
            else {
                $package = ( defined($1) && $1 ) ? $1 : $current_package;
                $package =~ s/\'/::/g;
                if ( $package =~ /^\:/ ) { $package = 'main' . $package }
                $package =~ s/::$//;
            }

            my $pos  = pos($input_line);
            my $numc = $pos - $pos_beg;
            $tok  = 'sub ' . substr( $input_line, $pos_beg, $numc );
            $type = 'i';

            # remember the sub name in case another call is needed to
            # get the prototype
            $package_saved = $package;
            $subname_saved = $subname;
        }

        # Now look for PROTO ATTRS for all call types
        # Look for prototype/attributes which are usually on the same
        # line as the sub name but which might be on a separate line.
        # For example, we might have an anonymous sub with attributes,
        # or a prototype on a separate line from its sub name

        # NOTE: We only want to parse PROTOTYPES here. If we see anything that
        # does not look like a prototype, we assume it is a SIGNATURE and we
        # will stop and let the the standard tokenizer handle it.  In
        # particular, we stop if we see any nested parens, braces, or commas.
        # Also note, a valid prototype cannot contain any alphabetic character
        #  -- see https://perldoc.perl.org/perlsub
        # But it appears that an underscore is valid in a prototype, so the
        # regex below uses [A-Za-z] rather than \w
        # This is the old regex which has been replaced:
        # $input_line =~ m/\G(\s*\([^\)\(\}\{\,#]*\))?  # PROTO
        my $saw_opening_paren = $input_line =~ /\G\s*\(/;
        if (
            $input_line =~ m/\G(\s*\([^\)\(\}\{\,#A-Za-z]*\))?  # PROTO
            (\s*:)?                              # ATTRS leading ':'
            /gcx
            && ( $1 || $2 )
          )
        {
            $proto = $1;
            $attrs = $2;

            # Append the prototype to the starting token if it is 'sub' or
            # 'prototype'.  This is not necessary but for compatibility with
            # previous versions when the -csc flag is used:
            if ( $proto && ( $match || $call_type == PROTOTYPE_CALL ) ) {
                $tok .= $proto;
            }

            # If we just entered the sub at an opening paren on this call, not
            # a following :prototype, label it with the previous token.  This is
            # necessary to propagate the sub name to its opening block.
            elsif ( $call_type == PAREN_CALL ) {
                $tok = $last_nonblank_token;
            }

            $match ||= 1;

            # Patch part #1 to fixes cases b994 and b1053:
            # Mark an anonymous sub keyword without prototype as type 'k', i.e.
            #    'sub : lvalue { ...'
            $type = 'i';
            if ( $tok eq 'sub' && !$proto ) { $type = 'k' }
        }

        if ($match) {

            # ATTRS: if there are attributes, back up and let the ':' be
            # found later by the scanner.
            my $pos = pos($input_line);
            if ($attrs) {
                $pos -= length($attrs);
            }

            my $next_nonblank_token = $tok;

            # catch case of line with leading ATTR ':' after anonymous sub
            if ( $pos == $pos_beg && $tok eq ':' ) {
                $type              = 'A';
                $in_attribute_list = 1;
            }

            # Otherwise, if we found a match we must convert back from
            # string position to the pre_token index for continued parsing.
            else {

                # I don't think an error flag can occur here ..but ?
                my $error;
                ( $i, $error ) = inverse_pretoken_map( $i, $pos, $rtoken_map,
                    $max_token_index );
                if ($error) { warning("Possibly invalid sub\n") }

                # Patch part #2 to fixes cases b994 and b1053:
                # Do not let spaces be part of the token of an anonymous sub
                # keyword which we marked as type 'k' above...i.e. for
                # something like:
                #    'sub : lvalue { ...'
                # Back up and let it be parsed as a blank
                if (   $type eq 'k'
                    && $attrs
                    && $i > $i_entry
                    && substr( $rtokens->[$i], 0, 1 ) =~ m/\s/ )
                {
                    $i--;
                }

                # check for multiple definitions of a sub
                ( $next_nonblank_token, my $i_next ) =
                  find_next_nonblank_token_on_this_line( $i, $rtokens,
                    $max_token_index );
            }

            if ( $next_nonblank_token =~ /^(\s*|#)$/ )
            {    # skip blank or side comment
                my ( $rpre_tokens, $rpre_types ) =
                  peek_ahead_for_n_nonblank_pre_tokens(1);
                if ( defined($rpre_tokens) && @{$rpre_tokens} ) {
                    $next_nonblank_token = $rpre_tokens->[0];
                }
                else {
                    $next_nonblank_token = '}';
                }
            }

            # See what's next...
            if ( $next_nonblank_token eq '{' ) {
                if ($subname) {

                    # Check for multiple definitions of a sub, but
                    # it is ok to have multiple sub BEGIN, etc,
                    # so we do not complain if name is all caps
                    if (   $saw_function_definition{$subname}{$package}
                        && $subname !~ /^[A-Z]+$/ )
                    {
                        my $lno = $saw_function_definition{$subname}{$package};
                        if ( $package =~ /^\d/ ) {
                            warning(
"already saw definition of lexical 'sub $subname' at line $lno\n"
                            );

                        }
                        else {
                            warning(
"already saw definition of 'sub $subname' in package '$package' at line $lno\n"
                            ) unless (DEVEL_MODE);
                        }
                    }
                    $saw_function_definition{$subname}{$package} =
                      $tokenizer_self->[_last_line_number_];
                }
            }
            elsif ( $next_nonblank_token eq ';' ) {
            }
            elsif ( $next_nonblank_token eq '}' ) {
            }

            # ATTRS - if an attribute list follows, remember the name
            # of the sub so the next opening brace can be labeled.
            # Setting 'statement_type' causes any ':'s to introduce
            # attributes.
            elsif ( $next_nonblank_token eq ':' ) {
                if ( $call_type == SUB_CALL ) {
                    $statement_type =
                      substr( $tok, 0, 3 ) eq 'sub' ? $tok : 'sub';
                }
            }

            # if we stopped before an open paren ...
            elsif ( $next_nonblank_token eq '(' ) {

                # If we DID NOT see this paren above then it must be on the
                # next line so we will set a flag to come back here and see if
                # it is a PROTOTYPE

                # Otherwise, we assume it is a SIGNATURE rather than a
                # PROTOTYPE and let the normal tokenizer handle it as a list
                if ( !$saw_opening_paren ) {
                    $id_scan_state = 'sub';    # we must come back to get proto
                }
                if ( $call_type == SUB_CALL ) {
                    $statement_type =
                      substr( $tok, 0, 3 ) eq 'sub' ? $tok : 'sub';
                }
            }
            elsif ($next_nonblank_token) {    # EOF technically ok
                $subname = "" unless defined($subname);
                warning(
"expecting ':' or ';' or '{' after definition or declaration of sub '$subname' but saw '$next_nonblank_token'\n"
                );
            }
            check_prototype( $proto, $package, $subname );
        }

        # no match to either sub name or prototype, but line not blank
        else {

        }
        return ( $i, $tok, $type, $id_scan_state );
    }
}

#########i###############################################################
# Tokenizer utility routines which may use CONSTANTS but no other GLOBALS
#########################################################################

sub find_next_nonblank_token {
    my ( $i, $rtokens, $max_token_index ) = @_;

    # Returns the next nonblank token after the token at index $i
    # To skip past a side comment, and any subsequent block comments
    # and blank lines, call with i=$max_token_index

    if ( $i >= $max_token_index ) {
        if ( !peeked_ahead() ) {
            peeked_ahead(1);
            peek_ahead_for_nonblank_token( $rtokens, $max_token_index );
        }
    }

    my $next_nonblank_token = $rtokens->[ ++$i ];
    return ( " ", $i ) unless defined($next_nonblank_token);

    if ( $next_nonblank_token =~ /^\s*$/ ) {
        $next_nonblank_token = $rtokens->[ ++$i ];
        return ( " ", $i ) unless defined($next_nonblank_token);
    }
    return ( $next_nonblank_token, $i );
}

sub find_next_noncomment_type {
    my ( $i, $rtokens, $max_token_index ) = @_;

    # Given the current character position, look ahead past any comments
    # and blank lines and return the next token, including digraphs and
    # trigraphs.

    my ( $next_nonblank_token, $i_next ) =
      find_next_nonblank_token( $i, $rtokens, $max_token_index );

    # skip past any side comment
    if ( $next_nonblank_token eq '#' ) {
        ( $next_nonblank_token, $i_next ) =
          find_next_nonblank_token( $i_next, $rtokens, $max_token_index );
    }

    goto RETURN if ( !$next_nonblank_token || $next_nonblank_token eq " " );

    # check for possible a digraph
    goto RETURN if ( !defined( $rtokens->[ $i_next + 1 ] ) );
    my $test2 = $next_nonblank_token . $rtokens->[ $i_next + 1 ];
    goto RETURN if ( !$is_digraph{$test2} );
    $next_nonblank_token = $test2;
    $i_next              = $i_next + 1;

    # check for possible a trigraph
    goto RETURN if ( !defined( $rtokens->[ $i_next + 1 ] ) );
    my $test3 = $next_nonblank_token . $rtokens->[ $i_next + 1 ];
    goto RETURN if ( !$is_trigraph{$test3} );
    $next_nonblank_token = $test3;
    $i_next              = $i_next + 1;

  RETURN:
    return ( $next_nonblank_token, $i_next );
}

sub is_possible_numerator {

    # Look at the next non-comment character and decide if it could be a
    # numerator.  Return
    #   1 - yes
    #   0 - can't tell
    #  -1 - no

    my ( $i, $rtokens, $max_token_index ) = @_;
    my $is_possible_numerator = 0;

    my $next_token = $rtokens->[ $i + 1 ];
    if ( $next_token eq '=' ) { $i++; }    # handle /=
    my ( $next_nonblank_token, $i_next ) =
      find_next_nonblank_token( $i, $rtokens, $max_token_index );

    if ( $next_nonblank_token eq '#' ) {
        ( $next_nonblank_token, $i_next ) =
          find_next_nonblank_token( $max_token_index, $rtokens,
            $max_token_index );
    }

    if ( $next_nonblank_token =~ /(\(|\$|\w|\.|\@)/ ) {
        $is_possible_numerator = 1;
    }
    elsif ( $next_nonblank_token =~ /^\s*$/ ) {
        $is_possible_numerator = 0;
    }
    else {
        $is_possible_numerator = -1;
    }

    return $is_possible_numerator;
}

{    ## closure for sub pattern_expected
    my %pattern_test;

    BEGIN {

        # List of tokens which may follow a pattern.  Note that we will not
        # have formed digraphs at this point, so we will see '&' instead of
        # '&&' and '|' instead of '||'

        # /(\)|\}|\;|\&\&|\|\||and|or|while|if|unless)/
        my @q = qw( & && | || ? : + - * and or while if unless);
        push @q, ')', '}', ']', '>', ',', ';';
        @{pattern_test}{@q} = (1) x scalar(@q);
    }

    sub pattern_expected {

        # This a filter for a possible pattern.
        # It looks at the token after a possible pattern and tries to
        # determine if that token could end a pattern.
        # returns -
        #   1 - yes
        #   0 - can't tell
        #  -1 - no
        my ( $i, $rtokens, $max_token_index ) = @_;
        my $is_pattern = 0;

        my $next_token = $rtokens->[ $i + 1 ];
        if ( $next_token =~ /^[msixpodualgc]/ ) {
            $i++;
        }    # skip possible modifier
        my ( $next_nonblank_token, $i_next ) =
          find_next_nonblank_token( $i, $rtokens, $max_token_index );

        if ( $pattern_test{$next_nonblank_token} ) {
            $is_pattern = 1;
        }
        else {

            # Added '#' to fix issue c044
            if (   $next_nonblank_token =~ /^\s*$/
                || $next_nonblank_token eq '#' )
            {
                $is_pattern = 0;
            }
            else {
                $is_pattern = -1;
            }
        }
        return $is_pattern;
    }
}

sub find_next_nonblank_token_on_this_line {
    my ( $i, $rtokens, $max_token_index ) = @_;
    my $next_nonblank_token;

    if ( $i < $max_token_index ) {
        $next_nonblank_token = $rtokens->[ ++$i ];

        if ( $next_nonblank_token =~ /^\s*$/ ) {

            if ( $i < $max_token_index ) {
                $next_nonblank_token = $rtokens->[ ++$i ];
            }
        }
    }
    else {
        $next_nonblank_token = "";
    }
    return ( $next_nonblank_token, $i );
}

sub find_angle_operator_termination {

    # We are looking at a '<' and want to know if it is an angle operator.
    # We are to return:
    #   $i = pretoken index of ending '>' if found, current $i otherwise
    #   $type = 'Q' if found, '>' otherwise
    my ( $input_line, $i_beg, $rtoken_map, $expecting, $max_token_index ) = @_;
    my $i    = $i_beg;
    my $type = '<';
    pos($input_line) = 1 + $rtoken_map->[$i];

    my $filter;

    # we just have to find the next '>' if a term is expected
    if ( $expecting == TERM ) { $filter = '[\>]' }

    # we have to guess if we don't know what is expected
    elsif ( $expecting == UNKNOWN ) { $filter = '[\>\;\=\#\|\<]' }

    # shouldn't happen - we shouldn't be here if operator is expected
    else {
        if (DEVEL_MODE) {
            Fault(<<EOM);
Bad call to find_angle_operator_termination
EOM
        }
        return ( $i, $type );
    }

    # To illustrate what we might be looking at, in case we are
    # guessing, here are some examples of valid angle operators
    # (or file globs):
    #  <tmp_imp/*>
    #  <FH>
    #  <$fh>
    #  <*.c *.h>
    #  <_>
    #  <jskdfjskdfj* op/* jskdjfjkosvk*> ( glob.t)
    #  <${PREFIX}*img*.$IMAGE_TYPE>
    #  <img*.$IMAGE_TYPE>
    #  <Timg*.$IMAGE_TYPE>
    #  <$LATEX2HTMLVERSIONS${dd}html[1-9].[0-9].pl>
    #
    # Here are some examples of lines which do not have angle operators:
    #  return unless $self->[2]++ < $#{$self->[1]};
    #  < 2  || @$t >
    #
    # the following line from dlister.pl caused trouble:
    #  print'~'x79,"\n",$D<1024?"0.$D":$D>>10,"K, $C files\n\n\n";
    #
    # If the '<' starts an angle operator, it must end on this line and
    # it must not have certain characters like ';' and '=' in it.  I use
    # this to limit the testing.  This filter should be improved if
    # possible.

    if ( $input_line =~ /($filter)/g ) {

        if ( $1 eq '>' ) {

            # We MAY have found an angle operator termination if we get
            # here, but we need to do more to be sure we haven't been
            # fooled.
            my $pos = pos($input_line);

            my $pos_beg = $rtoken_map->[$i];
            my $str     = substr( $input_line, $pos_beg, ( $pos - $pos_beg ) );

            # Test for '<' after possible filehandle, issue c103
            # print $fh <>;          # syntax error
            # print $fh <DATA>;      # ok
            # print $fh < DATA>;     # syntax error at '>'
            # print STDERR < DATA>;  # ok, prints word 'DATA'
            # print BLABLA <DATA>;   # ok; does nothing unless BLABLA is defined
            if ( $last_nonblank_type eq 'Z' ) {

                # $str includes brackets; something like '<DATA>'
                if (   substr( $last_nonblank_token, 0, 1 ) !~ /[A-Za-z_]/
                    && substr( $str, 1, 1 ) !~ /[A-Za-z_]/ )
                {
                    return ( $i, $type );
                }
            }

            # Reject if the closing '>' follows a '-' as in:
            # if ( VERSION < 5.009 && $op-> name eq 'assign' ) { }
            if ( $expecting eq UNKNOWN ) {
                my $check = substr( $input_line, $pos - 2, 1 );
                if ( $check eq '-' ) {
                    return ( $i, $type );
                }
            }

            ######################################debug#####
            #write_diagnostics( "ANGLE? :$str\n");
            #print "ANGLE: found $1 at pos=$pos str=$str check=$check\n";
            ######################################debug#####
            $type = 'Q';
            my $error;
            ( $i, $error ) =
              inverse_pretoken_map( $i, $pos, $rtoken_map, $max_token_index );

            # It may be possible that a quote ends midway in a pretoken.
            # If this happens, it may be necessary to split the pretoken.
            if ($error) {
                if (DEVEL_MODE) {
                    Fault(<<EOM);
unexpected error condition returned by inverse_pretoken_map
EOM
                }
                warning(
                    "Possible tokinization error..please check this line\n");
            }

            # count blanks on inside of brackets
            my $blank_count = 0;
            $blank_count++ if ( $str =~ /<\s+/ );
            $blank_count++ if ( $str =~ /\s+>/ );

            # Now let's see where we stand....
            # OK if math op not possible
            if ( $expecting == TERM ) {
            }

            # OK if there are no more than 2 non-blank pre-tokens inside
            # (not possible to write 2 token math between < and >)
            # This catches most common cases
            elsif ( $i <= $i_beg + 3 + $blank_count ) {

                # No longer any need to document this common case
                ## write_diagnostics("ANGLE(1 or 2 tokens): $str\n");
            }

            # OK if there is some kind of identifier inside
            #   print $fh <tvg::INPUT>;
            elsif ( $str =~ /^<\s*\$?(\w|::|\s)+\s*>$/ ) {
                write_diagnostics("ANGLE (contains identifier): $str\n");
            }

            # Not sure..
            else {

                # Let's try a Brace Test: any braces inside must balance
                my $br = 0;
                while ( $str =~ /\{/g ) { $br++ }
                while ( $str =~ /\}/g ) { $br-- }
                my $sb = 0;
                while ( $str =~ /\[/g ) { $sb++ }
                while ( $str =~ /\]/g ) { $sb-- }
                my $pr = 0;
                while ( $str =~ /\(/g ) { $pr++ }
                while ( $str =~ /\)/g ) { $pr-- }

                # if braces do not balance - not angle operator
                if ( $br || $sb || $pr ) {
                    $i    = $i_beg;
                    $type = '<';
                    write_diagnostics(
                        "NOT ANGLE (BRACE={$br ($pr [$sb ):$str\n");
                }

                # we should keep doing more checks here...to be continued
                # Tentatively accepting this as a valid angle operator.
                # There are lots more things that can be checked.
                else {
                    write_diagnostics(
                        "ANGLE-Guessing yes: $str expecting=$expecting\n");
                    write_logfile_entry("Guessing angle operator here: $str\n");
                }
            }
        }

        # didn't find ending >
        else {
            if ( $expecting == TERM ) {
                warning("No ending > for angle operator\n");
            }
        }
    }
    return ( $i, $type );
}

sub scan_number_do {

    #  scan a number in any of the formats that Perl accepts
    #  Underbars (_) are allowed in decimal numbers.
    #  input parameters -
    #      $input_line  - the string to scan
    #      $i           - pre_token index to start scanning
    #    $rtoken_map    - reference to the pre_token map giving starting
    #                    character position in $input_line of token $i
    #  output parameters -
    #    $i            - last pre_token index of the number just scanned
    #    number        - the number (characters); or undef if not a number

    my ( $input_line, $i, $rtoken_map, $input_type, $max_token_index ) = @_;
    my $pos_beg = $rtoken_map->[$i];
    my $pos;
    my $i_begin = $i;
    my $number  = undef;
    my $type    = $input_type;

    my $first_char = substr( $input_line, $pos_beg, 1 );

    # Look for bad starting characters; Shouldn't happen..
    if ( $first_char !~ /[\d\.\+\-Ee]/ ) {
        if (DEVEL_MODE) {
            Fault(<<EOM);
Program bug - scan_number given bad first character = '$first_char'
EOM
        }
        return ( $i, $type, $number );
    }

    # handle v-string without leading 'v' character ('Two Dot' rule)
    # (vstring.t)
    # Here is the format prior to including underscores:
    ## if ( $input_line =~ /\G((\d+)?\.\d+(\.\d+)+)/g ) {
    pos($input_line) = $pos_beg;
    if ( $input_line =~ /\G((\d[_\d]*)?\.[\d_]+(\.[\d_]+)+)/g ) {
        $pos = pos($input_line);
        my $numc = $pos - $pos_beg;
        $number = substr( $input_line, $pos_beg, $numc );
        $type   = 'v';
        report_v_string($number);
    }

    # handle octal, hex, binary
    if ( !defined($number) ) {
        pos($input_line) = $pos_beg;

        # Perl 5.22 added floating point literals, like '0x0.b17217f7d1cf78p0'
        # For reference, the format prior to hex floating point is:
        #   /\G[+-]?0(([xX][0-9a-fA-F_]+)|([0-7_]+)|([bB][01_]+))/g )
        #             (hex)               (octal)   (binary)
        if (
            $input_line =~

            /\G[+-]?0(                   # leading [signed] 0

           # a hex float, i.e. '0x0.b17217f7d1cf78p0'
           ([xX][0-9a-fA-F_]*            # X and optional leading digits
           (\.([0-9a-fA-F][0-9a-fA-F_]*)?)?   # optional decimal and fraction
           [Pp][+-]?[0-9a-fA-F]          # REQUIRED exponent with digit
           [0-9a-fA-F_]*)                # optional Additional exponent digits

           # or hex integer
           |([xX][0-9a-fA-F_]+)        

           # or octal fraction
           |([oO]?[0-7_]+          # string of octal digits
           (\.([0-7][0-7_]*)?)?    # optional decimal and fraction
           [Pp][+-]?[0-7]          # REQUIRED exponent, no underscore
           [0-7_]*)                # Additional exponent digits with underscores

           # or octal integer
           |([oO]?[0-7_]+)         # string of octal digits

           # or a binary float
           |([bB][01_]*            # 'b' with string of binary digits 
           (\.([01][01_]*)?)?      # optional decimal and fraction
           [Pp][+-]?[01]           # Required exponent indicator, no underscore
           [01_]*)                 # additional exponent bits

           # or binary integer
           |([bB][01_]+)           # 'b' with string of binary digits 

           )/gx
          )
        {
            $pos = pos($input_line);
            my $numc = $pos - $pos_beg;
            $number = substr( $input_line, $pos_beg, $numc );
            $type   = 'n';
        }
    }

    # handle decimal
    if ( !defined($number) ) {
        pos($input_line) = $pos_beg;

        if ( $input_line =~ /\G([+-]?[\d_]*(\.[\d_]*)?([Ee][+-]?(\d+))?)/g ) {
            $pos = pos($input_line);

            # watch out for things like 0..40 which would give 0. by this;
            if (   ( substr( $input_line, $pos - 1, 1 ) eq '.' )
                && ( substr( $input_line, $pos, 1 ) eq '.' ) )
            {
                $pos--;
            }
            my $numc = $pos - $pos_beg;
            $number = substr( $input_line, $pos_beg, $numc );
            $type   = 'n';
        }
    }

    # filter out non-numbers like e + - . e2  .e3 +e6
    # the rule: at least one digit, and any 'e' must be preceded by a digit
    if (
        $number !~ /\d/    # no digits
        || (   $number =~ /^(.*)[eE]/
            && $1 !~ /\d/ )    # or no digits before the 'e'
      )
    {
        $number = undef;
        $type   = $input_type;
        return ( $i, $type, $number );
    }

    # Found a number; now we must convert back from character position
    # to pre_token index. An error here implies user syntax error.
    # An example would be an invalid octal number like '009'.
    my $error;
    ( $i, $error ) =
      inverse_pretoken_map( $i, $pos, $rtoken_map, $max_token_index );
    if ($error) { warning("Possibly invalid number\n") }

    return ( $i, $type, $number );
}

sub inverse_pretoken_map {

    # Starting with the current pre_token index $i, scan forward until
    # finding the index of the next pre_token whose position is $pos.
    my ( $i, $pos, $rtoken_map, $max_token_index ) = @_;
    my $error = 0;

    while ( ++$i <= $max_token_index ) {

        if ( $pos <= $rtoken_map->[$i] ) {

            # Let the calling routine handle errors in which we do not
            # land on a pre-token boundary.  It can happen by running
            # perltidy on some non-perl scripts, for example.
            if ( $pos < $rtoken_map->[$i] ) { $error = 1 }
            $i--;
            last;
        }
    }
    return ( $i, $error );
}

sub find_here_doc {

    # find the target of a here document, if any
    # input parameters:
    #   $i - token index of the second < of <<
    #   ($i must be less than the last token index if this is called)
    # output parameters:
    #   $found_target = 0 didn't find target; =1 found target
    #   HERE_TARGET - the target string (may be empty string)
    #   $i - unchanged if not here doc,
    #    or index of the last token of the here target
    #   $saw_error - flag noting unbalanced quote on here target
    my ( $expecting, $i, $rtokens, $rtoken_map, $max_token_index ) = @_;
    my $ibeg                 = $i;
    my $found_target         = 0;
    my $here_doc_target      = '';
    my $here_quote_character = '';
    my $saw_error            = 0;
    my ( $next_nonblank_token, $i_next_nonblank, $next_token );
    $next_token = $rtokens->[ $i + 1 ];

    # perl allows a backslash before the target string (heredoc.t)
    my $backslash = 0;
    if ( $next_token eq '\\' ) {
        $backslash  = 1;
        $next_token = $rtokens->[ $i + 2 ];
    }

    ( $next_nonblank_token, $i_next_nonblank ) =
      find_next_nonblank_token_on_this_line( $i, $rtokens, $max_token_index );

    if ( $next_nonblank_token =~ /[\'\"\`]/ ) {

        my $in_quote    = 1;
        my $quote_depth = 0;
        my $quote_pos   = 0;
        my $quoted_string;

        (
            $i, $in_quote, $here_quote_character, $quote_pos, $quote_depth,
            $quoted_string
          )
          = follow_quoted_string( $i_next_nonblank, $in_quote, $rtokens,
            $here_quote_character, $quote_pos, $quote_depth, $max_token_index );

        if ($in_quote) {    # didn't find end of quote, so no target found
            $i = $ibeg;
            if ( $expecting == TERM ) {
                warning(
"Did not find here-doc string terminator ($here_quote_character) before end of line \n"
                );
                $saw_error = 1;
            }
        }
        else {              # found ending quote
            $found_target = 1;

            my $tokj;
            foreach my $j ( $i_next_nonblank + 1 .. $i - 1 ) {
                $tokj = $rtokens->[$j];

                # we have to remove any backslash before the quote character
                # so that the here-doc-target exactly matches this string
                next
                  if ( $tokj eq "\\"
                    && $j < $i - 1
                    && $rtokens->[ $j + 1 ] eq $here_quote_character );
                $here_doc_target .= $tokj;
            }
        }
    }

    elsif ( ( $next_token =~ /^\s*$/ ) and ( $expecting == TERM ) ) {
        $found_target = 1;
        write_logfile_entry(
            "found blank here-target after <<; suggest using \"\"\n");
        $i = $ibeg;
    }
    elsif ( $next_token =~ /^\w/ ) {    # simple bareword or integer after <<

        my $here_doc_expected;
        if ( $expecting == UNKNOWN ) {
            $here_doc_expected = guess_if_here_doc($next_token);
        }
        else {
            $here_doc_expected = 1;
        }

        if ($here_doc_expected) {
            $found_target    = 1;
            $here_doc_target = $next_token;
            $i               = $ibeg + 1;
        }

    }
    else {

        if ( $expecting == TERM ) {
            $found_target = 1;
            write_logfile_entry("Note: bare here-doc operator <<\n");
        }
        else {
            $i = $ibeg;
        }
    }

    # patch to neglect any prepended backslash
    if ( $found_target && $backslash ) { $i++ }

    return ( $found_target, $here_doc_target, $here_quote_character, $i,
        $saw_error );
}

sub do_quote {

    # follow (or continue following) quoted string(s)
    # $in_quote return code:
    #   0 - ok, found end
    #   1 - still must find end of quote whose target is $quote_character
    #   2 - still looking for end of first of two quotes
    #
    # Returns updated strings:
    #  $quoted_string_1 = quoted string seen while in_quote=1
    #  $quoted_string_2 = quoted string seen while in_quote=2
    my (
        $i,               $in_quote,    $quote_character,
        $quote_pos,       $quote_depth, $quoted_string_1,
        $quoted_string_2, $rtokens,     $rtoken_map,
        $max_token_index
    ) = @_;

    my $in_quote_starting = $in_quote;

    my $quoted_string;
    if ( $in_quote == 2 ) {    # two quotes/quoted_string_1s to follow
        my $ibeg = $i;
        (
            $i, $in_quote, $quote_character, $quote_pos, $quote_depth,
            $quoted_string
          )
          = follow_quoted_string( $i, $in_quote, $rtokens, $quote_character,
            $quote_pos, $quote_depth, $max_token_index );
        $quoted_string_2 .= $quoted_string;
        if ( $in_quote == 1 ) {
            if ( $quote_character =~ /[\{\[\<\(]/ ) { $i++; }
            $quote_character = '';
        }
        else {
            $quoted_string_2 .= "\n";
        }
    }

    if ( $in_quote == 1 ) {    # one (more) quote to follow
        my $ibeg = $i;
        (
            $i, $in_quote, $quote_character, $quote_pos, $quote_depth,
            $quoted_string
          )
          = follow_quoted_string( $ibeg, $in_quote, $rtokens, $quote_character,
            $quote_pos, $quote_depth, $max_token_index );
        $quoted_string_1 .= $quoted_string;
        if ( $in_quote == 1 ) {
            $quoted_string_1 .= "\n";
        }
    }
    return ( $i, $in_quote, $quote_character, $quote_pos, $quote_depth,
        $quoted_string_1, $quoted_string_2 );
}

sub follow_quoted_string {

    # scan for a specific token, skipping escaped characters
    # if the quote character is blank, use the first non-blank character
    # input parameters:
    #   $rtokens = reference to the array of tokens
    #   $i = the token index of the first character to search
    #   $in_quote = number of quoted strings being followed
    #   $beginning_tok = the starting quote character
    #   $quote_pos = index to check next for alphanumeric delimiter
    # output parameters:
    #   $i = the token index of the ending quote character
    #   $in_quote = decremented if found end, unchanged if not
    #   $beginning_tok = the starting quote character
    #   $quote_pos = index to check next for alphanumeric delimiter
    #   $quote_depth = nesting depth, since delimiters '{ ( [ <' can be nested.
    #   $quoted_string = the text of the quote (without quotation tokens)
    my ( $i_beg, $in_quote, $rtokens, $beginning_tok, $quote_pos, $quote_depth,
        $max_token_index )
      = @_;
    my ( $tok, $end_tok );
    my $i             = $i_beg - 1;
    my $quoted_string = "";

    0 && do {
        print STDOUT
"QUOTE entering with quote_pos = $quote_pos i=$i beginning_tok =$beginning_tok\n";
    };

    # get the corresponding end token
    if ( $beginning_tok !~ /^\s*$/ ) {
        $end_tok = matching_end_token($beginning_tok);
    }

    # a blank token means we must find and use the first non-blank one
    else {
        my $allow_quote_comments = ( $i < 0 ) ? 1 : 0; # i<0 means we saw a <cr>

        while ( $i < $max_token_index ) {
            $tok = $rtokens->[ ++$i ];

            if ( $tok !~ /^\s*$/ ) {

                if ( ( $tok eq '#' ) && ($allow_quote_comments) ) {
                    $i = $max_token_index;
                }
                else {

                    if ( length($tok) > 1 ) {
                        if ( $quote_pos <= 0 ) { $quote_pos = 1 }
                        $beginning_tok = substr( $tok, $quote_pos - 1, 1 );
                    }
                    else {
                        $beginning_tok = $tok;
                        $quote_pos     = 0;
                    }
                    $end_tok     = matching_end_token($beginning_tok);
                    $quote_depth = 1;
                    last;
                }
            }
            else {
                $allow_quote_comments = 1;
            }
        }
    }

    # There are two different loops which search for the ending quote
    # character.  In the rare case of an alphanumeric quote delimiter, we
    # have to look through alphanumeric tokens character-by-character, since
    # the pre-tokenization process combines multiple alphanumeric
    # characters, whereas for a non-alphanumeric delimiter, only tokens of
    # length 1 can match.

    ###################################################################
    # Case 1 (rare): loop for case of alphanumeric quote delimiter..
    # "quote_pos" is the position the current word to begin searching
    ###################################################################
    if ( $beginning_tok =~ /\w/ ) {

        # Note this because it is not recommended practice except
        # for obfuscated perl contests
        if ( $in_quote == 1 ) {
            write_logfile_entry(
                "Note: alphanumeric quote delimiter ($beginning_tok) \n");
        }

        # Note: changed < to <= here to fix c109. Relying on extra end blanks.
        while ( $i <= $max_token_index ) {

            if ( $quote_pos == 0 || ( $i < 0 ) ) {
                $tok = $rtokens->[ ++$i ];

                if ( $tok eq '\\' ) {

                    # retain backslash unless it hides the end token
                    $quoted_string .= $tok
                      unless $rtokens->[ $i + 1 ] eq $end_tok;
                    $quote_pos++;
                    last if ( $i >= $max_token_index );
                    $tok = $rtokens->[ ++$i ];
                }
            }
            my $old_pos = $quote_pos;

            unless ( defined($tok) && defined($end_tok) && defined($quote_pos) )
            {

            }
            $quote_pos = 1 + index( $tok, $end_tok, $quote_pos );

            if ( $quote_pos > 0 ) {

                $quoted_string .=
                  substr( $tok, $old_pos, $quote_pos - $old_pos - 1 );

                # NOTE: any quote modifiers will be at the end of '$tok'. If we
                # wanted to check them, this is the place to get them.  But
                # this quote form is rarely used in practice, so it isn't
                # worthwhile.

                $quote_depth--;

                if ( $quote_depth == 0 ) {
                    $in_quote--;
                    last;
                }
            }
            else {
                if ( $old_pos <= length($tok) ) {
                    $quoted_string .= substr( $tok, $old_pos );
                }
            }
        }
    }

    ########################################################################
    # Case 2 (normal): loop for case of a non-alphanumeric quote delimiter..
    ########################################################################
    else {

        while ( $i < $max_token_index ) {
            $tok = $rtokens->[ ++$i ];

            if ( $tok eq $end_tok ) {
                $quote_depth--;

                if ( $quote_depth == 0 ) {
                    $in_quote--;
                    last;
                }
            }
            elsif ( $tok eq $beginning_tok ) {
                $quote_depth++;
            }
            elsif ( $tok eq '\\' ) {

                # retain backslash unless it hides the beginning or end token
                $tok = $rtokens->[ ++$i ];
                $quoted_string .= '\\'
                  unless ( $tok eq $end_tok || $tok eq $beginning_tok );
            }
            $quoted_string .= $tok;
        }
    }
    if ( $i > $max_token_index ) { $i = $max_token_index }
    return ( $i, $in_quote, $beginning_tok, $quote_pos, $quote_depth,
        $quoted_string );
}

sub indicate_error {
    my ( $msg, $line_number, $input_line, $pos, $carrat ) = @_;
    interrupt_logfile();
    warning($msg);
    write_error_indicator_pair( $line_number, $input_line, $pos, $carrat );
    resume_logfile();
    return;
}

sub write_error_indicator_pair {
    my ( $line_number, $input_line, $pos, $carrat ) = @_;
    my ( $offset, $numbered_line, $underline ) =
      make_numbered_line( $line_number, $input_line, $pos );
    $underline = write_on_underline( $underline, $pos - $offset, $carrat );
    warning( $numbered_line . "\n" );
    $underline =~ s/\s*$//;
    warning( $underline . "\n" );
    return;
}

sub make_numbered_line {

    #  Given an input line, its line number, and a character position of
    #  interest, create a string not longer than 80 characters of the form
    #     $lineno: sub_string
    #  such that the sub_string of $str contains the position of interest
    #
    #  Here is an example of what we want, in this case we add trailing
    #  '...' because the line is long.
    #
    # 2: (One of QAML 2.0's authors is a member of the World Wide Web Con ...
    #
    #  Here is another example, this time in which we used leading '...'
    #  because of excessive length:
    #
    # 2: ... er of the World Wide Web Consortium's
    #
    #  input parameters are:
    #   $lineno = line number
    #   $str = the text of the line
    #   $pos = position of interest (the error) : 0 = first character
    #
    #   We return :
    #     - $offset = an offset which corrects the position in case we only
    #       display part of a line, such that $pos-$offset is the effective
    #       position from the start of the displayed line.
    #     - $numbered_line = the numbered line as above,
    #     - $underline = a blank 'underline' which is all spaces with the same
    #       number of characters as the numbered line.

    my ( $lineno, $str, $pos ) = @_;
    my $offset = ( $pos < 60 ) ? 0 : $pos - 40;
    my $excess = length($str) - $offset - 68;
    my $numc   = ( $excess > 0 ) ? 68 : undef;

    if ( defined($numc) ) {
        if ( $offset == 0 ) {
            $str = substr( $str, $offset, $numc - 4 ) . " ...";
        }
        else {
            $str = "... " . substr( $str, $offset + 4, $numc - 4 ) . " ...";
        }
    }
    else {

        if ( $offset == 0 ) {
        }
        else {
            $str = "... " . substr( $str, $offset + 4 );
        }
    }

    my $numbered_line = sprintf( "%d: ", $lineno );
    $offset -= length($numbered_line);
    $numbered_line .= $str;
    my $underline = " " x length($numbered_line);
    return ( $offset, $numbered_line, $underline );
}

sub write_on_underline {

    # The "underline" is a string that shows where an error is; it starts
    # out as a string of blanks with the same length as the numbered line of
    # code above it, and we have to add marking to show where an error is.
    # In the example below, we want to write the string '--^' just below
    # the line of bad code:
    #
    # 2: (One of QAML 2.0's authors is a member of the World Wide Web Con ...
    #                 ---^
    # We are given the current underline string, plus a position and a
    # string to write on it.
    #
    # In the above example, there will be 2 calls to do this:
    # First call:  $pos=19, pos_chr=^
    # Second call: $pos=16, pos_chr=---
    #
    # This is a trivial thing to do with substr, but there is some
    # checking to do.

    my ( $underline, $pos, $pos_chr ) = @_;

    # check for error..shouldn't happen
    unless ( ( $pos >= 0 ) && ( $pos <= length($underline) ) ) {
        return $underline;
    }
    my $excess = length($pos_chr) + $pos - length($underline);
    if ( $excess > 0 ) {
        $pos_chr = substr( $pos_chr, 0, length($pos_chr) - $excess );
    }
    substr( $underline, $pos, length($pos_chr) ) = $pos_chr;
    return ($underline);
}

sub pre_tokenize {

    # Break a string, $str, into a sequence of preliminary tokens.  We
    # are interested in these types of tokens:
    #   words       (type='w'),            example: 'max_tokens_wanted'
    #   digits      (type = 'd'),          example: '0755'
    #   whitespace  (type = 'b'),          example: '   '
    #   any other single character (i.e. punct; type = the character itself).
    # We cannot do better than this yet because we might be in a quoted
    # string or pattern.  Caller sets $max_tokens_wanted to 0 to get all
    # tokens.
    my ( $str, $max_tokens_wanted ) = @_;

    # we return references to these 3 arrays:
    my @tokens    = ();     # array of the tokens themselves
    my @token_map = (0);    # string position of start of each token
    my @type      = ();     # 'b'=whitespace, 'd'=digits, 'w'=alpha, or punct

    do {

        # whitespace
        if ( $str =~ /\G(\s+)/gc ) { push @type, 'b'; }

        # numbers
        # note that this must come before words!
        elsif ( $str =~ /\G(\d+)/gc ) { push @type, 'd'; }

        # words
        elsif ( $str =~ /\G(\w+)/gc ) { push @type, 'w'; }

        # single-character punctuation
        elsif ( $str =~ /\G(\W)/gc ) { push @type, $1; }

        # that's all..
        else {
            return ( \@tokens, \@token_map, \@type );
        }

        push @tokens,    $1;
        push @token_map, pos($str);

    } while ( --$max_tokens_wanted != 0 );

    return ( \@tokens, \@token_map, \@type );
}

sub show_tokens {

    # this is an old debug routine
    # not called, but saved for reference
    my ( $rtokens, $rtoken_map ) = @_;
    my $num = scalar( @{$rtokens} );

    foreach my $i ( 0 .. $num - 1 ) {
        my $len = length( $rtokens->[$i] );
        print STDOUT "$i:$len:$rtoken_map->[$i]:$rtokens->[$i]:\n";
    }
    return;
}

{    ## closure for sub matching end token
    my %matching_end_token;

    BEGIN {
        %matching_end_token = (
            '{' => '}',
            '(' => ')',
            '[' => ']',
            '<' => '>',
        );
    }

    sub matching_end_token {

        # return closing character for a pattern
        my $beginning_token = shift;
        if ( $matching_end_token{$beginning_token} ) {
            return $matching_end_token{$beginning_token};
        }
        return ($beginning_token);
    }
}

sub dump_token_types {
    my ( $class, $fh ) = @_;

    # This should be the latest list of token types in use
    # adding NEW_TOKENS: add a comment here
    $fh->print(<<'END_OF_LIST');

Here is a list of the token types currently used for lines of type 'CODE'.  
For the following tokens, the "type" of a token is just the token itself.  

.. :: << >> ** && .. || // -> => += -= .= %= &= |= ^= *= <>
( ) <= >= == =~ !~ != ++ -- /= x=
... **= <<= >>= &&= ||= //= <=> 
, + - / * | % ! x ~ = \ ? : . < > ^ &

The following additional token types are defined:

 type    meaning
    b    blank (white space) 
    {    indent: opening structural curly brace or square bracket or paren
         (code block, anonymous hash reference, or anonymous array reference)
    }    outdent: right structural curly brace or square bracket or paren
    [    left non-structural square bracket (enclosing an array index)
    ]    right non-structural square bracket
    (    left non-structural paren (all but a list right of an =)
    )    right non-structural paren
    L    left non-structural curly brace (enclosing a key)
    R    right non-structural curly brace 
    ;    terminal semicolon
    f    indicates a semicolon in a "for" statement
    h    here_doc operator <<
    #    a comment
    Q    indicates a quote or pattern
    q    indicates a qw quote block
    k    a perl keyword
    C    user-defined constant or constant function (with void prototype = ())
    U    user-defined function taking parameters
    G    user-defined function taking block parameter (like grep/map/eval)
    M    (unused, but reserved for subroutine definition name)
    P    (unused, but -html uses it to label pod text)
    t    type indicater such as %,$,@,*,&,sub
    w    bare word (perhaps a subroutine call)
    i    identifier of some type (with leading %, $, @, *, &, sub, -> )
    n    a number
    v    a v-string
    F    a file test operator (like -e)
    Y    File handle
    Z    identifier in indirect object slot: may be file handle, object
    J    LABEL:  code block label
    j    LABEL after next, last, redo, goto
    p    unary +
    m    unary -
    pp   pre-increment operator ++
    mm   pre-decrement operator -- 
    A    : used as attribute separator
    
    Here are the '_line_type' codes used internally:
    SYSTEM         - system-specific code before hash-bang line
    CODE           - line of perl code (including comments)
    POD_START      - line starting pod, such as '=head'
    POD            - pod documentation text
    POD_END        - last line of pod section, '=cut'
    HERE           - text of here-document
    HERE_END       - last line of here-doc (target word)
    FORMAT         - format section
    FORMAT_END     - last line of format section, '.'
    SKIP           - code skipping section
    SKIP_END       - last line of code skipping section, '#>>V'
    DATA_START     - __DATA__ line
    DATA           - unidentified text following __DATA__
    END_START      - __END__ line
    END            - unidentified text following __END__
    ERROR          - we are in big trouble, probably not a perl script
END_OF_LIST

    return;
}

BEGIN {

    # These names are used in error messages
    @opening_brace_names = qw# '{' '[' '(' '?' #;
    @closing_brace_names = qw# '}' ']' ')' ':' #;

    my @q;

    my @digraphs = qw(
      .. :: << >> ** && .. || // -> => += -= .= %= &= |= ^= *= <>
      <= >= == =~ !~ != ++ -- /= x= ~~ ~. |. &. ^.
    );
    @is_digraph{@digraphs} = (1) x scalar(@digraphs);

    my @trigraphs = qw( ... **= <<= >>= &&= ||= //= <=> !~~ &.= |.= ^.= <<~);
    @is_trigraph{@trigraphs} = (1) x scalar(@trigraphs);

    my @tetragraphs = qw( <<>> );
    @is_tetragraph{@tetragraphs} = (1) x scalar(@tetragraphs);

    # make a hash of all valid token types for self-checking the tokenizer
    # (adding NEW_TOKENS : select a new character and add to this list)
    my @valid_token_types = qw#
      A b C G L R f h Q k t w i q n p m F pp mm U j J Y Z v
      { } ( ) [ ] ; + - / * | % ! x ~ = \ ? : . < > ^ &
      #;
    push( @valid_token_types, @digraphs );
    push( @valid_token_types, @trigraphs );
    push( @valid_token_types, @tetragraphs );
    push( @valid_token_types, ( '#', ',', 'CORE::' ) );
    @is_valid_token_type{@valid_token_types} = (1) x scalar(@valid_token_types);

    # a list of file test letters, as in -e (Table 3-4 of 'camel 3')
    my @file_test_operators =
      qw( A B C M O R S T W X b c d e f g k l o p r s t u w x z);
    @is_file_test_operator{@file_test_operators} =
      (1) x scalar(@file_test_operators);

    # these functions have prototypes of the form (&), so when they are
    # followed by a block, that block MAY BE followed by an operator.
    # Smartmatch operator ~~ may be followed by anonymous hash or array ref
    @q = qw( do eval );
    @is_block_operator{@q} = (1) x scalar(@q);

    # these functions allow an identifier in the indirect object slot
    @q = qw( print printf sort exec system say);
    @is_indirect_object_taker{@q} = (1) x scalar(@q);

    # These tokens may precede a code block
    # patched for SWITCH/CASE/CATCH.  Actually these could be removed
    # now and we could let the extended-syntax coding handle them.
    # Added 'default' for Switch::Plain.
    @q =
      qw( BEGIN END CHECK INIT AUTOLOAD DESTROY UNITCHECK continue if elsif else
      unless do while until eval for foreach map grep sort
      switch case given when default catch try finally);
    @is_code_block_token{@q} = (1) x scalar(@q);

    # Note: this hash was formerly named '%is_not_zero_continuation_block_type'
    # to contrast it with the block types in '%is_zero_continuation_block_type'
    @q = qw( sort map grep eval do );
    @is_sort_map_grep_eval_do{@q} = (1) x scalar(@q);

    %is_grep_alias = ();

    # I'll build the list of keywords incrementally
    my @Keywords = ();

    # keywords and tokens after which a value or pattern is expected,
    # but not an operator.  In other words, these should consume terms
    # to their right, or at least they are not expected to be followed
    # immediately by operators.
    my @value_requestor = qw(
      AUTOLOAD
      BEGIN
      CHECK
      DESTROY
      END
      EQ
      GE
      GT
      INIT
      LE
      LT
      NE
      UNITCHECK
      abs
      accept
      alarm
      and
      atan2
      bind
      binmode
      bless
      break
      caller
      chdir
      chmod
      chomp
      chop
      chown
      chr
      chroot
      close
      closedir
      cmp
      connect
      continue
      cos
      crypt
      dbmclose
      dbmopen
      defined
      delete
      die
      dump
      each
      else
      elsif
      eof
      eq
      evalbytes
      exec
      exists
      exit
      exp
      fc
      fcntl
      fileno
      flock
      for
      foreach
      formline
      ge
      getc
      getgrgid
      getgrnam
      gethostbyaddr
      gethostbyname
      getnetbyaddr
      getnetbyname
      getpeername
      getpgrp
      getpriority
      getprotobyname
      getprotobynumber
      getpwnam
      getpwuid
      getservbyname
      getservbyport
      getsockname
      getsockopt
      glob
      gmtime
      goto
      grep
      gt
      hex
      if
      index
      int
      ioctl
      join
      keys
      kill
      last
      lc
      lcfirst
      le
      length
      link
      listen
      local
      localtime
      lock
      log
      lstat
      lt
      map
      mkdir
      msgctl
      msgget
      msgrcv
      msgsnd
      my
      ne
      next
      no
      not
      oct
      open
      opendir
      or
      ord
      our
      pack
      pipe
      pop
      pos
      print
      printf
      prototype
      push
      quotemeta
      rand
      read
      readdir
      readlink
      readline
      readpipe
      recv
      redo
      ref
      rename
      require
      reset
      return
      reverse
      rewinddir
      rindex
      rmdir
      scalar
      seek
      seekdir
      select
      semctl
      semget
      semop
      send
      sethostent
      setnetent
      setpgrp
      setpriority
      setprotoent
      setservent
      setsockopt
      shift
      shmctl
      shmget
      shmread
      shmwrite
      shutdown
      sin
      sleep
      socket
      socketpair
      sort
      splice
      split
      sprintf
      sqrt
      srand
      stat
      state
      study
      substr
      symlink
      syscall
      sysopen
      sysread
      sysseek
      system
      syswrite
      tell
      telldir
      tie
      tied
      truncate
      uc
      ucfirst
      umask
      undef
      unless
      unlink
      unpack
      unshift
      untie
      until
      use
      utime
      values
      vec
      waitpid
      warn
      while
      write
      xor

      switch
      case
      default
      given
      when
      err
      say
      isa

      catch
    );

    # patched above for SWITCH/CASE given/when err say
    # 'err' is a fairly safe addition.
    # Added 'default' for Switch::Plain. Note that we could also have
    # a separate set of keywords to include if we see 'use Switch::Plain'
    push( @Keywords, @value_requestor );

    # These are treated the same but are not keywords:
    my @extra_vr = qw(
      constant
      vars
    );
    push( @value_requestor, @extra_vr );

    @expecting_term_token{@value_requestor} = (1) x scalar(@value_requestor);

    # this list contains keywords which do not look for arguments,
    # so that they might be followed by an operator, or at least
    # not a term.
    my @operator_requestor = qw(
      endgrent
      endhostent
      endnetent
      endprotoent
      endpwent
      endservent
      fork
      getgrent
      gethostent
      getlogin
      getnetent
      getppid
      getprotoent
      getpwent
      getservent
      setgrent
      setpwent
      time
      times
      wait
      wantarray
    );

    push( @Keywords, @operator_requestor );

    # These are treated the same but are not considered keywords:
    my @extra_or = qw(
      STDERR
      STDIN
      STDOUT
    );

    push( @operator_requestor, @extra_or );

    @expecting_operator_token{@operator_requestor} =
      (1) x scalar(@operator_requestor);

    # these token TYPES expect trailing operator but not a term
    # note: ++ and -- are post-increment and decrement, 'C' = constant
    my @operator_requestor_types = qw( ++ -- C <> q );
    @expecting_operator_types{@operator_requestor_types} =
      (1) x scalar(@operator_requestor_types);

    # these token TYPES consume values (terms)
    # note: pp and mm are pre-increment and decrement
    # f=semicolon in for,  F=file test operator
    my @value_requestor_type = qw#
      L { ( [ ~ !~ =~ ; . .. ... A : && ! || // = + - x
      **= += -= .= /= *= %= x= &= |= ^= <<= >>= &&= ||= //=
      <= >= == != => \ > < % * / ? & | ** <=> ~~ !~~ <<~
      f F pp mm Y p m U J G j >> << ^ t
      ~. ^. |. &. ^.= |.= &.=
      #;
    push( @value_requestor_type, ',' )
      ;    # (perl doesn't like a ',' in a qw block)
    @expecting_term_types{@value_requestor_type} =
      (1) x scalar(@value_requestor_type);

    # Note: the following valid token types are not assigned here to
    # hashes requesting to be followed by values or terms, but are
    # instead currently hard-coded into sub operator_expected:
    # ) -> :: Q R Z ] b h i k n v w } #

    # For simple syntax checking, it is nice to have a list of operators which
    # will really be unhappy if not followed by a term.  This includes most
    # of the above...
    %really_want_term = %expecting_term_types;

    # with these exceptions...
    delete $really_want_term{'U'}; # user sub, depends on prototype
    delete $really_want_term{'F'}; # file test works on $_ if no following term
    delete $really_want_term{'Y'}; # indirect object, too risky to check syntax;
                                   # let perl do it

    @q = qw(q qq qw qx qr s y tr m);
    @is_q_qq_qw_qx_qr_s_y_tr_m{@q} = (1) x scalar(@q);

    @q = qw(package);
    @is_package{@q} = (1) x scalar(@q);

    @q = qw( ? : );
    push @q, ',';
    @is_comma_question_colon{@q} = (1) x scalar(@q);

    # Hash of other possible line endings which may occur.
    # Keep these coordinated with the regex where this is used.
    # Note: chr(13) = chr(015)="\r".
    @q = ( chr(13), chr(29), chr(26) );
    @other_line_endings{@q} = (1) x scalar(@q);

    # These keywords are handled specially in the tokenizer code:
    my @special_keywords = qw(
      do
      eval
      format
      m
      package
      q
      qq
      qr
      qw
      qx
      s
      sub
      tr
      y
    );
    push( @Keywords, @special_keywords );

    # Keywords after which list formatting may be used
    # WARNING: do not include |map|grep|eval or perl may die on
    # syntax errors (map1.t).
    my @keyword_taking_list = qw(
      and
      chmod
      chomp
      chop
      chown
      dbmopen
      die
      elsif
      exec
      fcntl
      for
      foreach
      formline
      getsockopt
      if
      index
      ioctl
      join
      kill
      local
      msgctl
      msgrcv
      msgsnd
      my
      open
      or
      our
      pack
      print
      printf
      push
      read
      readpipe
      recv
      return
      reverse
      rindex
      seek
      select
      semctl
      semget
      send
      setpriority
      setsockopt
      shmctl
      shmget
      shmread
      shmwrite
      socket
      socketpair
      sort
      splice
      split
      sprintf
      state
      substr
      syscall
      sysopen
      sysread
      sysseek
      system
      syswrite
      tie
      unless
      unlink
      unpack
      unshift
      until
      vec
      warn
      while
      given
      when
    );
    @is_keyword_taking_list{@keyword_taking_list} =
      (1) x scalar(@keyword_taking_list);

    # perl functions which may be unary operators.

    # This list is used to decide if a pattern delimited by slashes, /pattern/,
    # can follow one of these keywords.
    @q = qw(
      chomp eof eval fc lc pop shift uc undef
    );

    @is_keyword_rejecting_slash_as_pattern_delimiter{@q} =
      (1) x scalar(@q);

    # These are keywords for which an arg may optionally be omitted.  They are
    # currently only used to disambiguate a ? used as a ternary from one used
    # as a (depricated) pattern delimiter.  In the future, they might be used
    # to give a warning about ambiguous syntax before a /.
    # Note: split has been omitted (see not below).
    my @keywords_taking_optional_arg = qw(
      abs
      alarm
      caller
      chdir
      chomp
      chop
      chr
      chroot
      close
      cos
      defined
      die
      eof
      eval
      evalbytes
      exit
      exp
      fc
      getc
      glob
      gmtime
      hex
      int
      last
      lc
      lcfirst
      length
      localtime
      log
      lstat
      mkdir
      next
      oct
      ord
      pop
      pos
      print
      printf
      prototype
      quotemeta
      rand
      readline
      readlink
      readpipe
      redo
      ref
      require
      reset
      reverse
      rmdir
      say
      select
      shift
      sin
      sleep
      sqrt
      srand
      stat
      study
      tell
      uc
      ucfirst
      umask
      undef
      unlink
      warn
      write
    );
    @is_keyword_taking_optional_arg{@keywords_taking_optional_arg} =
      (1) x scalar(@keywords_taking_optional_arg);

    # This list is used to decide if a pattern delmited by question marks,
    # ?pattern?, can follow one of these keywords.  Note that from perl 5.22
    # on, a ?pattern? is not recognized, so we can be much more strict than
    # with a /pattern/. Note that 'split' is not in this list. In current
    # versions of perl a question following split must be a ternary, but
    # in older versions it could be a pattern.  The guessing algorithm will
    # decide.  We are combining two lists here to simplify the test.
    @q = ( @keywords_taking_optional_arg, @operator_requestor );
    @is_keyword_rejecting_question_as_pattern_delimiter{@q} =
      (1) x scalar(@q);

    # These are not used in any way yet
    #    my @unused_keywords = qw(
    #     __FILE__
    #     __LINE__
    #     __PACKAGE__
    #     );

    #  The list of keywords was originally extracted from function 'keyword' in
    #  perl file toke.c version 5.005.03, using this utility, plus a
    #  little editing: (file getkwd.pl):
    #  while (<>) { while (/\"(.*)\"/g) { print "$1\n"; } }
    #  Add 'get' prefix where necessary, then split into the above lists.
    #  This list should be updated as necessary.
    #  The list should not contain these special variables:
    #  ARGV DATA ENV SIG STDERR STDIN STDOUT
    #  __DATA__ __END__

    @is_keyword{@Keywords} = (1) x scalar(@Keywords);
}
1;

use TAP::Entry;

package TAP {
	class Generator { ... }
	role Context does TAP::Entry::Handler {
		has TAP::Entry::Handler:D $.output;
		has Int $.tests-expected;
		has Int $.failed = 0;
		has Int $.tests-seen = 0;
		method emit(TAP::Entry) { ... }
		method subtest() { ... }
		method handle-entry(TAP::Entry $entry) {
			given ($entry) {
				when TAP::Plan {
					$!tests-expected = $entry.tests;
				}
				when TAP::Test {
					$!tests-seen++;
					$!failed++ if !$entry.is-ok();
				}
			}
			self.emit($entry);
		}
		method end-entries() {
			if $!tests-expected.defined && $!tests-seen != $!tests-expected {
				self.handle-entry(TAP::Comment.new(:comment("Expected $!tests-expected tests but seen $!tests-seen")));
			}
		}
	}

	my class Context::Sub does Context {
		has Str $.description;
		has TAP::Entry @!entries;
		method emit(TAP::Entry $entry) {
			@!entries.push($entry);
		}
		method subtest(Str $description) {
			return Context::Sub.new(:$!output, :$description);
		}
		method end-entries() {
			if !$!tests-expected.defined {
				self.handle-entry(TAP::Plan.new(:tests($!tests-seen)));
			}
			nextsame;
		}
		method give-test() {
			return TAP::Sub-Test.new(:ok(!$.failed), :$!description, :@!entries);
		}
	}
	my class Context::Main does Context {
		method emit(TAP::Entry $entry) {
			$!output.handle-entry($entry);
		}
		method subtest(Str $description) {
			return Context::Sub.new(:$!output, :$description);
		}
	}
	class Generator {
		has Int $.version;
		has TAP::Entry::Handler:D $.output;
		has Context @!constack;
		has Context $!context;
		submethod BUILD(TAP::Entry::Handler :$!output, Int :$!version = 12) {
			$!context = Context::Main.new(:$!output);
			$!output.handle-entry(TAP::Version.new($!version)) if $!version > 12;
		}

		multi method plan(Int $tests) {
			$!context.handle-entry(TAP::Plan.new(:tests($tests)));
		}
		multi method plan(Bool :$skip-all) {
			$!context.handle-entry(TAP::Plan.new(:tests(0), :skip-all));
		}
		multi method plan(TAP::Directive::Explanation :$skip-all) {
			$!context.handle-entry(TAP::Plan.new(:tests(0), :skip-all, :explanation($skip-all)));
		}

		method test(Bool :$ok, TAP::Test::Description :$description, TAP::Directive :$directive = TAP::No-Directive, TAP::Directive::Explanation :$explanation) {
			my $number = $!context.tests-seen + 1;
			$!context.handle-entry(TAP::Test.new(:$ok, :$number, :$description, :$directive, :$explanation));
		}
		method done-testing(Int $tests = $!context.tests-seen) {
			$!context.handle-entry(TAP::Plan.new(:$tests));
		}
		method comment(Str $comment) {
			for @( $comment.split(/\n/) ) -> $line {
				$!context.handle-entry(TAP::Comment.new(:comment($line)));
			}
		}
		method start-subtest(Str $description) {
			@!constack.push($!context);
			$!context = $!context.subtest($description);
			self.comment($description) if $description.defined;
		}
		method stop-subtest() {
			if @!constack {
				$!context.end-entries();
				my $old = $!context;
				$!context = @!constack.pop;
				$!context.handle-entry($old.give-test());
			}
			else {
				fail 'No subtests to return from';
			}
		}
		method stop-tests() {
			self.stop-subtest() while @!constack;
			$!output.end-entries();
			return min($!context.failed, 254);
		}
	}
}

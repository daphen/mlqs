package config

import "testing"

// The driving case: hide one bot that mails via GitHub without hiding GitHub.
// All of these arrive from notifications@github.com, so the sender ADDRESS alone
// cannot separate them — only the AND of address + display name can.
func TestRuleSeparatesBotFromSameAddress(t *testing.T) {
	bot := []Address{{Name: "lovable-ci-bot[bot]", Email: "notifications@github.com"}}
	human := []Address{{Name: "Khodor Ammar", Email: "notifications@github.com"}}

	tight := Rule{SenderEmail: "notifications@github.com", SenderName: "lovable-ci-bot[bot]"}
	if !tight.Match(bot, "Re: [lovablelabs/lovable] fix(web)") {
		t.Fatal("tight rule must hide the bot")
	}
	if tight.Match(human, "Re: [lovablelabs/lovable] fix(web)") {
		t.Fatal("tight rule must NOT hide a human from the same address")
	}

	loose := Rule{SenderEmail: "notifications@github.com"}
	if !loose.Match(bot, "x") || !loose.Match(human, "x") {
		t.Fatal("loose rule is expected to hide both — that's the trade-off the UI surfaces")
	}
}

func TestRuleFieldsAreANDed(t *testing.T) {
	s := []Address{{Name: "Bot", Email: "a@b.com"}}
	if (Rule{SenderEmail: "a@b.com", Subject: "deploy"}).Match(s, "build failed") {
		t.Fatal("subject must also match when set")
	}
	if !(Rule{SenderEmail: "a@b.com", Subject: "deploy"}).Match(s, "deploy green") {
		t.Fatal("both fields matching should hide")
	}
}

// An empty rule must never hide everything — a half-filled form in the UI would
// otherwise blank the whole mailbox.
func TestEmptyRuleMatchesNothing(t *testing.T) {
	if (Rule{}).Match([]Address{{Email: "x@y.z"}}, "anything") {
		t.Fatal("empty rule must not match")
	}
	if MatchAny([]Rule{{}}, []Address{{Email: "x@y.z"}}, "anything") {
		t.Fatal("MatchAny with only an empty rule must not match")
	}
}

func TestMatchIsCaseInsensitiveAndSubstringByDefault(t *testing.T) {
	s := []Address{{Name: "Lovable-CI-Bot[bot]", Email: "Notifications@GitHub.com"}}
	if !(Rule{SenderEmail: "github.com"}).Match(s, "") {
		t.Fatal("substring, case-insensitive by default")
	}
	if (Rule{SenderEmail: "github.com", Exact: true}).Match(s, "") {
		t.Fatal("exact must require the whole field")
	}
	if !(Rule{SenderEmail: "notifications@github.com", Exact: true}).Match(s, "") {
		t.Fatal("exact should match the full address regardless of case")
	}
}

// Any sender in the thread counts, so a noisy participant can't escape by
// replying last.
func TestMatchesAnySenderInThread(t *testing.T) {
	s := []Address{{Name: "Human", Email: "me@x.com"}, {Name: "Bot", Email: "noise@y.com"}}
	if !(Rule{SenderEmail: "noise@y.com"}).Match(s, "") {
		t.Fatal("should match a non-latest sender")
	}
}

# Security policy

This policy applies to every public repository of the Sealambda organization
that has no `SECURITY.md` of its own.

A private repository is outside this policy, because GitHub offers private
vulnerability reporting for public repositories only. Report a vulnerability
in a private repository to the maintainers of that repository.

## Supported versions

The default branch (`main`) and the latest tag of each component receive
security fixes. A component is a part of a repository that has its own tags
in the form `<component>-vN`.

## Report a vulnerability

Report a vulnerability privately, with
[GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability).
Never report it in a public issue, pull request or discussion.

1. Open the **Security and quality** tab of the repository. If the tab is
   hidden, open the menu at the end of the tabs and select it. The page
   `https://github.com/sealambda/<repository>/security/advisories/new` opens
   the form directly. Replace `<repository>` with the name of the repository.
2. Select **Report a vulnerability**, fill in the form and submit it. GitHub
   notifies the maintainers, and adds you as a collaborator and a credited
   user on the proposed advisory.

If the repository has no **Report a vulnerability** button, or the page is not
found, the repository does not accept private reports. Open the issue form
**Request a security contact** on the **New issue** page of the repository.
The form asks for the name of the repository and nothing else. The issue is
public, so put no detail of the vulnerability in it. A maintainer answers
with a private channel. A repository with issue templates of its own may have
no such form. Then open any issue that asks for a security contact, and put
no detail of the vulnerability in it.

## What to include

- A summary of the vulnerability and its impact: who is affected and how.
- The steps to reproduce it, or a proof of concept.
- The affected version or commit of the repository.
- A fix or a mitigation, if you have one.

## What to expect

- A maintainer reads the report and may ask you for more detail.
- The maintainers work on the fix in private, in the advisory.
- The maintainers publish the advisory when the fix is available, and credit
  you if you agree.

These targets are goals. They do not bind the maintainers:

- The maintainers acknowledge a report within 5 business days.
- The maintainers disclose a vulnerability in coordination with you within
  90 days of the report.

## Safe harbor

The maintainers treat research in good faith that follows this policy as
authorized, and they do not take legal action over it. Research follows this
policy when it reports through the channels above, accesses no more data than
the proof requires, does not degrade a service, and keeps the vulnerability
private until the coordinated disclosure. The statement covers the
repositories under this policy. It makes no promise about any other system of
the organization, and it cannot cover the systems of other parties.

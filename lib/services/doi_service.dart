/// DOI / publisher-URL helpers for the search bar's "Fetch" flow.
///
/// ACM and most publishers sit behind a Cloudflare JS challenge, so the app's
/// http client can't download their PDFs directly (a plain GET returns a 403
/// challenge page, not the PDF). Only the user's browser session — which passes
/// the challenge and carries their subscription/institutional access — can. So
/// for a DOI URL we resolve the DOI and hand the download off to the browser.
class DoiService {
  DoiService._();

  // A DOI is `10.<registrant>/<suffix>`; grab it from a raw string or a URL
  // (doi.org/…, dl.acm.org/doi[/pdf|/epdf|/abs]/…).
  // ponytail: covers the common publisher URL shapes; exotic DOIs with spaces
  // or angle brackets in the suffix aren't handled (they don't occur in URLs).
  static final RegExp _doiPattern =
      RegExp(r'10\.\d{4,9}/[^\s"<>?#]+', caseSensitive: false);

  /// Extract a DOI from an ACM/doi.org URL or a raw DOI string; null if none.
  static String? extractDoi(String input) {
    final match = _doiPattern.firstMatch(input.trim());
    if (match == null) return null;
    // Drop stray trailing punctuation the greedy match can swallow.
    return match.group(0)!.replaceAll(RegExp(r'[).,;]+$'), '');
  }

  /// True for ACM DL and doi.org URLs we can hand to the browser.
  static bool isDoiUrl(String input) {
    final v = input.trim().toLowerCase();
    final looksLikeUrl =
        v.contains('doi.org/10.') || v.contains('dl.acm.org/doi/');
    return looksLikeUrl && extractDoi(input) != null;
  }

  /// Best browser URL to reach the PDF for [input]'s DOI.
  /// ACM → its /doi/pdf/ endpoint; anything else → the doi.org resolver.
  static String pdfBrowserUrl(String input) {
    final doi = extractDoi(input);
    if (doi == null) return input;
    if (input.toLowerCase().contains('dl.acm.org')) {
      return 'https://dl.acm.org/doi/pdf/$doi';
    }
    return 'https://doi.org/$doi';
  }
}

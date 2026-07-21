import 'package:flutter_test/flutter_test.dart';
import 'package:paper_suitecase/services/doi_service.dart';

void main() {
  const doi = '10.1145/3768292.3770377';

  test('extracts DOI from ACM landing, epdf, and doi.org URLs', () {
    expect(DoiService.extractDoi('https://dl.acm.org/doi/$doi'), doi);
    expect(DoiService.extractDoi('https://dl.acm.org/doi/epdf/$doi'), doi);
    expect(DoiService.extractDoi('https://doi.org/$doi'), doi);
    expect(DoiService.extractDoi('transformer attention'), isNull);
  });

  test('detects ACM + doi.org URLs, not searches or arXiv', () {
    expect(DoiService.isDoiUrl('https://dl.acm.org/doi/$doi'), isTrue);
    expect(DoiService.isDoiUrl('https://dl.acm.org/doi/epdf/$doi'), isTrue);
    expect(DoiService.isDoiUrl('https://doi.org/$doi'), isTrue);
    expect(DoiService.isDoiUrl('multi-agent debate'), isFalse);
    expect(DoiService.isDoiUrl('https://arxiv.org/abs/1706.03762'), isFalse);
  });

  test('ACM URLs resolve to the /doi/pdf/ endpoint; others to doi.org', () {
    expect(DoiService.pdfBrowserUrl('https://dl.acm.org/doi/$doi'),
        'https://dl.acm.org/doi/pdf/$doi');
    expect(DoiService.pdfBrowserUrl('https://dl.acm.org/doi/epdf/$doi'),
        'https://dl.acm.org/doi/pdf/$doi');
    expect(DoiService.pdfBrowserUrl('https://doi.org/$doi'),
        'https://doi.org/$doi');
  });
}

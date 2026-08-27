import 'package:flutter_test/flutter_test.dart';
import 'package:paper_suitecase/models/paper.dart';
import 'package:paper_suitecase/widgets/download_dialog.dart';

Paper _p(int entryId, String filePath, String title) =>
    Paper(title: title, filePath: filePath, entryId: entryId);

void main() {
  test('significantTitleWords drops short words and stop-words', () {
    expect(
      significantTitleWords('Fiber Optic Sensing Glove for the Hand'),
      {'fiber', 'optic', 'sensing', 'glove', 'hand'},
    );
  });

  test('picks the entry + subfolder of the most title-relevant paper', () {
    final corpus = [
      _p(1, 'Diffusion/video.pdf', 'Video Diffusion Models'),
      _p(1, 'Hands/glove.pdf', 'A Sensing Glove for Dexterous Manipulation'),
      _p(1, 'Misc/other.pdf', 'Financial Deep Research'),
    ];
    final loc = suggestFolderByTitle(
      'Fiber Optic Sensing Glove for Dexterous Manipulation Capture',
      corpus,
      {1},
    );
    expect(loc, isNotNull);
    expect(loc!.subfolder, 'Hands'); // shares sensing/glove/dexterous/manipulation
  });

  test('distinctive shared words outweigh common ones (IDF)', () {
    // "learning"/"model" are common across the library (low weight);
    // "sensing"/"glove" are rare (high weight). The rare-word folder must win
    // even though both candidates share exactly two query words.
    final corpus = [
      _p(1, 'FVV/a.pdf', 'Deep Learning Model for Video'),
      _p(1, 'EmbeddedAI/b.pdf', 'Wearable Sensing Glove System'),
      _p(1, 'X/c.pdf', 'Learning Model Optimization'),
      _p(1, 'Y/d.pdf', 'Reinforcement Learning Model'),
      _p(1, 'Z/e.pdf', 'Generative Model Learning'),
    ];
    final loc =
        suggestFolderByTitle('Sensing Glove Learning Model', corpus, {1});
    expect(loc!.subfolder, 'EmbeddedAI');
  });

  test('a root-level best match yields the empty (root) subfolder', () {
    final loc = suggestFolderByTitle(
      'Dexterous Manipulation Capture',
      [_p(2, 'paper.pdf', 'Dexterous Manipulation Survey')],
      {2},
    );
    expect(loc!.subfolder, '');
  });

  test('returns null below the overlap floor or with no known entry', () {
    // Only 1 shared significant word ("models") — below the floor of 2.
    expect(
      suggestFolderByTitle('Diffusion Models',
          [_p(1, 'a/b.pdf', 'World Models for Robots')], {1}),
      isNull,
    );
    // Good match, but its entry is not known.
    expect(
      suggestFolderByTitle('Sensing Glove Manipulation',
          [_p(9, 'x/y.pdf', 'Sensing Glove Manipulation')], {1, 2}),
      isNull,
    );
  });
}

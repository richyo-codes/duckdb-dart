import 'dart:convert';
import 'dart:io';

import '../hook/native_source.dart';

Future<void> main(List<String> args) async {
  try {
    final options = <String, String>{};
    for (var i = 0; i < args.length; i += 2) {
      if (!{'--target', '--output', '--jobs'}.contains(args[i]) ||
          i + 1 >= args.length) {
        throw const FormatException(
          'Usage: dart tools/build_native.dart --target TARGET --output DIRECTORY [--jobs 2]',
        );
      }
      options[args[i]] = args[i + 1];
    }
    if (!options.containsKey('--target') || !options.containsKey('--output')) {
      throw const FormatException('--target and --output are required.');
    }
    final config =
        jsonDecode(
              await File.fromUri(
                Platform.script.resolve('../hook/native_config.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final library = await buildNativeSource(
      config: config,
      target: options['--target']!,
      output: Directory(options['--output']!),
      jobs: int.parse(options['--jobs'] ?? '2'),
    );
    stdout.writeln(library.path);
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

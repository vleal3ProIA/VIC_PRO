import 'package:flutter/widgets.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/features/account/domain/failures/profile_failure.dart';

String profileFailureMessage(BuildContext context, ProfileFailure failure) {
  final l = context.l10n;
  return switch (failure) {
    ProfileUsernameTaken() => l.profileErrorUsernameTaken,
    ProfileNotFound() => l.profileErrorNotFound,
    ProfileNetworkError() => l.profileErrorNetwork,
    ProfileInvalidImage() => l.profileErrorInvalidImage,
    ProfileUnknown() => l.profileErrorUnknown,
  };
}

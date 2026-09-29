import '../models/core_models.dart';
import '../models/team_models.dart';
import '../models/work_models.dart';

/// Who may change a project's settings, mirroring the server's rule.
///
/// The server lets two groups patch a project (`PATCH /projects/{id}`), move its
/// event date (schedule preview and apply), swap its picture and edit its time
/// settings:
///
/// * its **leads**, and
/// * the **Team-Admins of a team that owns it** (the project is listed in that
///   team's `projectIds`).
///
/// The platform `ADMIN` role opens none of this. An admin who is neither lead
/// nor Team-Admin of an owning team is refused like anybody else, so the app
/// must not offer the controls either: a button that always answers 403 is
/// worse than no button.
///
/// [myTeams] is what `GET /teams` returned for [me]. That list is membership
/// scoped on the server, so a team that owns the project but does not count
/// [me] as a member never shows up and never grants anything here.
bool canManageProject(Project project, AuthUser? me, Iterable<Team> myTeams) {
  if (me == null) return false;
  if (isProjectLead(project, me)) return true;
  for (final team in myTeams) {
    if (!team.projectIds.contains(project.id)) continue;
    if (team.membershipOf(me.id)?.isAdmin == true) return true;
  }
  return false;
}

/// Whether [me] leads [project].
///
/// The actions that stay with the leads alone use this rather than
/// [canManageProject]: deleting the project, attaching it to a team, connecting
/// a git repository and deciding timesheets. A Team-Admin of an owning team gets
/// the settings, never these.
bool isProjectLead(Project project, AuthUser? me) =>
    me != null && project.leadIds.contains(me.id);

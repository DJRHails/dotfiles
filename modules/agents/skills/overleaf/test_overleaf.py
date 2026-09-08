"""Tests for overleaf.py — page parsing, project resolution, and the push diff.

Every HTTP call is intercepted with `responses`, and the socket.io frame stream is
replaced by a fixture, so nothing here touches the network or a real Overleaf session.

Run: uv run --no-project --with pytest,responses,pydantic,requests,rich,typer,\
websocket-client pytest test_overleaf.py -q
"""

import http.cookiejar
import json

import pytest
import responses
import typer
import websocket

import overleaf

PROJECT_ID = "6aa025104d6398f6e090368d"
OTHER_ID = "1bb136215e74a907f1a1479e"
ROOT_FOLDER_ID = "6aa025104d6398f6e0903690"


@pytest.fixture(autouse=True)
def _isolate_session(monkeypatch, tmp_path):
    """Give every test a configured session, never the host's real one."""
    monkeypatch.setenv("OVERLEAF_SESSION_COOKIE", "s%3Atest-session")
    monkeypatch.delenv("OVERLEAF_GCLB_COOKIE", raising=False)
    monkeypatch.delenv("OVERLEAF_HOST", raising=False)
    monkeypatch.setattr(overleaf, "_CONFIG_DIR", tmp_path / "absent")


@pytest.fixture
def jar():
    return overleaf.cookies()


def _url(path: str) -> str:
    return f"https://{overleaf.DEFAULT_HOST}{path}"


def _meta(name: str, payload: object) -> str:
    """A page carrying one `ol-*` meta, HTML-escaped the way Overleaf emits it."""
    content = (
        json.dumps(payload).replace('"', "&quot;") if not isinstance(payload, str) else payload
    )
    return f'<html><head><meta name="ol-{name}" content="{content}"></head></html>'


def _projects_page(*projects: object) -> str:
    body = json.dumps({"projects": list(projects)}).replace('"', "&quot;")
    return (
        '<html><head><meta name="ol-csrfToken" content="tok-dashboard">'
        f'<meta name="ol-prefetchedProjectsBlob" content="{body}"></head></html>'
    )


def _project(project_id: str, name: str, **extra: object) -> dict:
    record = {
        "id": project_id,
        "name": name,
        "lastUpdated": "2026-09-08T00:00:00.000Z",
        "accessLevel": "owner",
        "archived": False,
        "trashed": False,
        "owner": {"id": "u1", "email": "daniel@hails.info", "firstName": "Daniel"},
    }
    record.update(extra)
    return record


# --- session resolution -----------------------------------------------------------------------
def test_session_cookie_from_env(jar):
    names = {cookie.name: cookie.value for cookie in jar}
    assert names == {overleaf.SESSION_COOKIE: "s%3Atest-session"}


def test_sticky_cookie_travels_when_set(monkeypatch):
    monkeypatch.setenv("OVERLEAF_GCLB_COOKIE", "lb-pin")
    names = {cookie.name: cookie.value for cookie in overleaf.cookies()}
    assert names[overleaf.STICKY_COOKIE] == "lb-pin"


def test_missing_session_refuses_with_guidance(monkeypatch, capsys):
    monkeypatch.delenv("OVERLEAF_SESSION_COOKIE")
    with pytest.raises(typer.Exit) as caught:
        overleaf.cookies()
    assert caught.value.exit_code == 2
    assert overleaf.SESSION_COOKIE in capsys.readouterr().err


def test_cookie_domain_drops_the_www():
    assert overleaf._cookie_domain() == ".overleaf.com"


def test_self_hosted_host_from_env(monkeypatch):
    monkeypatch.setenv("OVERLEAF_HOST", "latex.example.org")
    assert overleaf.overleaf_host() == "latex.example.org"
    assert overleaf._cookie_domain() == ".latex.example.org"


def test_env_file_fills_gaps_without_overriding(monkeypatch, tmp_path):
    config = tmp_path / ".config" / "overleaf"
    config.mkdir(parents=True)
    (config / "env").write_text(
        "# a comment\nexport OVERLEaF_IGNORED=1\nexport OVERLEAF_HOST='latex.example.org'\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(overleaf.Path, "home", staticmethod(lambda: tmp_path))
    monkeypatch.setenv("OVERLEAF_SESSION_COOKIE", "already-set")
    overleaf._load_env_file()
    assert overleaf.overleaf_host() == "latex.example.org"
    assert overleaf.os.environ["OVERLEAF_SESSION_COOKIE"] == "already-set"


# --- page metas -------------------------------------------------------------------------------
def test_page_metas_unescapes_json_content():
    page = _meta("prefetchedProjectsBlob", {"projects": [{"id": PROJECT_ID, "name": 'A "quoted"'}]})
    blob = overleaf.meta_model(
        overleaf.page_metas(page), "prefetchedProjectsBlob", overleaf.ProjectsBlob
    )
    assert blob.projects[0].name == 'A "quoted"'


def test_page_metas_reads_name_after_content():
    page = '<html><meta content="tok-1" name="ol-csrfToken"></html>'
    assert overleaf.page_metas(page)["csrfToken"] == "tok-1"


def test_missing_meta_names_what_it_found(capsys):
    with pytest.raises(typer.Exit):
        overleaf.meta_model({"csrfToken": "t"}, "prefetchedProjectsBlob", overleaf.ProjectsBlob)
    assert "csrfToken" in capsys.readouterr().err


@responses.activate
def test_logged_out_redirect_refuses(jar, capsys):
    responses.get(_url("/project"), status=302, headers={"location": "/login"})
    with pytest.raises(typer.Exit) as caught:
        overleaf._get_page(jar, "/project")
    assert caught.value.exit_code == 2
    assert "expired" in capsys.readouterr().err


@responses.activate
def test_session_probe_reads_the_account(jar):
    responses.get(
        _url("/user/personal_info"),
        json={"id": "u1", "email": "daniel@hails.info", "firstName": "Daniel"},
    )
    assert overleaf.whoami_record(jar).label == "daniel@hails.info"


@responses.activate
def test_session_probe_refuses_when_unauthorised(jar):
    responses.get(_url("/user/personal_info"), status=401, json={})
    with pytest.raises(typer.Exit):
        overleaf.whoami_record(jar)


# --- project resolution -----------------------------------------------------------------------
def test_resolve_by_bare_id_skips_the_dashboard(jar):
    # No `responses` registration: resolving an id must issue no HTTP call at all.
    assert overleaf.resolve_project(jar, PROJECT_ID).id == PROJECT_ID


def test_resolve_by_project_url(jar):
    url = f"https://www.overleaf.com/project/{PROJECT_ID}"
    assert overleaf.resolve_project(jar, url).id == PROJECT_ID


@responses.activate
def test_resolve_by_exact_name(jar):
    responses.get(_url("/project"), body=_projects_page(_project(PROJECT_ID, "Monitor Bycatch")))
    assert overleaf.resolve_project(jar, "Monitor Bycatch").id == PROJECT_ID


@responses.activate
def test_resolve_by_substring_and_case(jar):
    responses.get(_url("/project"), body=_projects_page(_project(PROJECT_ID, "Monitor Bycatch")))
    assert overleaf.resolve_project(jar, "bycatch").id == PROJECT_ID


@responses.activate
def test_exact_name_wins_over_substring(jar):
    responses.get(
        _url("/project"),
        body=_projects_page(_project(PROJECT_ID, "Paper"), _project(OTHER_ID, "Paper draft")),
    )
    assert overleaf.resolve_project(jar, "Paper").id == PROJECT_ID


@responses.activate
def test_ambiguous_name_lists_candidates(jar, capsys):
    responses.get(
        _url("/project"),
        body=_projects_page(_project(PROJECT_ID, "draft one"), _project(OTHER_ID, "draft two")),
    )
    with pytest.raises(typer.Exit):
        overleaf.resolve_project(jar, "draft")
    captured = capsys.readouterr().err
    assert PROJECT_ID in captured and OTHER_ID in captured


@responses.activate
def test_trashed_projects_are_not_resolvable(jar):
    responses.get(_url("/project"), body=_projects_page(_project(PROJECT_ID, "Gone", trashed=True)))
    with pytest.raises(typer.Exit):
        overleaf.resolve_project(jar, "Gone")


@responses.activate
def test_unknown_name_refuses(jar, capsys):
    responses.get(_url("/project"), body=_projects_page(_project(PROJECT_ID, "Monitor Bycatch")))
    with pytest.raises(typer.Exit):
        overleaf.resolve_project(jar, "nothing like it")
    assert "projects list" in capsys.readouterr().err


# --- the project tree -------------------------------------------------------------------------
JOIN_FRAME = "5:::" + json.dumps(
    {
        "name": "joinProjectResponse",
        "args": [
            {
                "project": {
                    "rootFolder": [
                        {
                            "_id": ROOT_FOLDER_ID,
                            "name": "rootFolder",
                            "docs": [{"_id": "d1", "name": "main.tex"}],
                            "fileRefs": [{"_id": "f1", "name": "logo.png"}],
                            "folders": [
                                {
                                    "_id": "fold1",
                                    "name": "figures",
                                    "docs": [],
                                    "fileRefs": [{"_id": "f2", "name": "plot.png"}],
                                    "folders": [],
                                }
                            ],
                        }
                    ]
                }
            }
        ],
    }
)


@pytest.fixture
def tree(monkeypatch, jar):
    monkeypatch.setattr(overleaf, "_socket_frames", lambda _jar, _pid: iter(["1::", JOIN_FRAME]))
    return overleaf.project_tree(jar, PROJECT_ID)


def test_tree_carries_the_root_folder_id(tree):
    assert tree.root_folder_id == ROOT_FOLDER_ID


def test_tree_flattens_nested_paths_with_kinds(tree):
    assert {e.path: e.kind for e in tree.entities} == {
        "main.tex": "doc",
        "logo.png": "file",
        "figures": "folder",
        "figures/plot.png": "file",
    }


def test_tree_files_excludes_folders(tree):
    assert [e.path for e in tree.files()] == ["figures/plot.png", "logo.png", "main.tex"]


def test_socket_error_frame_refuses(monkeypatch, jar, capsys):
    monkeypatch.setattr(overleaf, "_socket_frames", lambda _jar, _pid: iter(["7:::not authorized"]))
    with pytest.raises(typer.Exit):
        overleaf.project_tree(jar, PROJECT_ID)
    assert "socket refused" in capsys.readouterr().err


def test_socket_closing_early_refuses(monkeypatch, jar, capsys):
    monkeypatch.setattr(overleaf, "_socket_frames", lambda _jar, _pid: iter(["1::", "2::"]))
    with pytest.raises(typer.Exit):
        overleaf.project_tree(jar, PROJECT_ID)
    assert "closed before" in capsys.readouterr().err


def test_socket_rejection_names_the_reason(monkeypatch, jar, capsys):
    rejected = "5:::" + json.dumps(
        {"name": "connectionRejected", "args": [{"message": "invalid session"}]}
    )
    monkeypatch.setattr(overleaf, "_socket_frames", lambda _jar, _pid: iter(["1::", rejected]))
    with pytest.raises(typer.Exit) as caught:
        overleaf.project_tree(jar, PROJECT_ID)
    assert caught.value.exit_code == 2
    assert "invalid session" in capsys.readouterr().err


class _HangingUpSocket:
    """A websocket the server closes after one frame, as Overleaf does on a rejected join."""

    def __init__(self):
        self.closed = False
        self._frames = iter(["1::"])

    def recv(self):
        try:
            return next(self._frames)
        except StopIteration:
            raise websocket.WebSocketConnectionClosedException(
                "Connection to remote host was lost."
            ) from None

    def close(self):
        self.closed = True


@responses.activate
def test_socket_frames_end_when_the_server_hangs_up(monkeypatch, jar):
    responses.get(_url("/socket.io/1/"), body="sid-1:60:60:websocket")
    fake = _HangingUpSocket()
    monkeypatch.setattr(websocket, "create_connection", lambda *_args, **_kwargs: fake)
    assert list(overleaf._socket_frames(jar, PROJECT_ID)) == ["1::"]
    assert fake.closed


def test_walk_folder_handles_an_empty_project():
    root = {"_id": ROOT_FOLDER_ID, "name": "rootFolder", "docs": [], "fileRefs": [], "folders": []}
    assert list(overleaf.walk_folder(root, prefix="")) == []


# --- reading entities -------------------------------------------------------------------------
@responses.activate
def test_read_doc_uses_the_doc_download_route(jar):
    responses.get(_url(f"/Project/{PROJECT_ID}/doc/d1/download"), body=b"\\documentclass{article}")
    entity = overleaf.RemoteEntity(path="main.tex", id="d1", kind="doc")
    assert overleaf.read_entity(jar, PROJECT_ID, entity) == b"\\documentclass{article}"


@responses.activate
def test_read_file_uses_the_file_route(jar):
    responses.get(_url(f"/project/{PROJECT_ID}/file/f1"), body=b"\x89PNG")
    entity = overleaf.RemoteEntity(path="logo.png", id="f1", kind="file")
    assert overleaf.read_entity(jar, PROJECT_ID, entity) == b"\x89PNG"


@responses.activate
def test_forbidden_read_names_the_session(jar, capsys):
    # Overleaf's project routes answer an expired cookie with a 403, not a login redirect.
    responses.get(_url(f"/project/{PROJECT_ID}/file/f1"), status=403, body="restricted")
    entity = overleaf.RemoteEntity(path="logo.png", id="f1", kind="file")
    with pytest.raises(typer.Exit) as caught:
        overleaf.read_entity(jar, PROJECT_ID, entity)
    assert caught.value.exit_code == 2
    assert "session" in capsys.readouterr().err


# --- the push diff ----------------------------------------------------------------------------
def test_local_files_skips_dot_paths(tmp_path):
    (tmp_path / "main.tex").write_text("x", encoding="utf-8")
    (tmp_path / "figures").mkdir()
    (tmp_path / "figures" / "plot.png").write_bytes(b"p")
    (tmp_path / ".git").mkdir()
    (tmp_path / ".git" / "HEAD").write_text("ref", encoding="utf-8")
    (tmp_path / ".DS_Store").write_text("junk", encoding="utf-8")
    assert sorted(overleaf.local_files(tmp_path)) == ["figures/plot.png", "main.tex"]


@pytest.mark.parametrize(
    ("remote", "local", "expected"),
    [
        (b"same", b"same", True),
        (b"same\n", b"same", True),
        (b"same", b"same\n", True),
        (b"same", b"different", False),
        (b"", b"", True),
    ],
)
def test_same_content_ignores_the_trailing_newline(remote, local, expected):
    assert overleaf.same_content(remote, local) is expected


@responses.activate
def test_plan_push_classifies_every_path(tree, jar, tmp_path):
    # main.tex differs, logo.png is byte-identical, extra.bib is new, figures/plot.png is gone.
    responses.get(_url(f"/Project/{PROJECT_ID}/doc/d1/download"), body=b"old body")
    responses.get(_url(f"/project/{PROJECT_ID}/file/f1"), body=b"\x89PNG")
    (tmp_path / "main.tex").write_bytes(b"new body")
    (tmp_path / "logo.png").write_bytes(b"\x89PNG")
    (tmp_path / "extra.bib").write_bytes(b"@book{x}")
    plan = overleaf.plan_push(jar, PROJECT_ID, tree, overleaf.local_files(tmp_path), prune=True)
    assert plan.added == ["extra.bib"]
    assert plan.replaced == ["main.tex"]
    assert plan.unchanged == ["logo.png"]
    assert [e.path for e in plan.pruned] == ["figures/plot.png"]
    assert plan.writes == ["extra.bib", "main.tex"]


@responses.activate
def test_plan_push_without_prune_keeps_remote_extras(tree, jar, tmp_path):
    responses.get(_url(f"/Project/{PROJECT_ID}/doc/d1/download"), body=b"body")
    (tmp_path / "main.tex").write_bytes(b"body")
    plan = overleaf.plan_push(jar, PROJECT_ID, tree, overleaf.local_files(tmp_path), prune=False)
    assert plan.pruned == []
    assert plan.is_empty()


@responses.activate
def test_plan_push_replaces_a_path_that_is_a_remote_folder(tree, jar, tmp_path):
    (tmp_path / "figures").write_bytes(b"now a file")
    plan = overleaf.plan_push(jar, PROJECT_ID, tree, overleaf.local_files(tmp_path), prune=False)
    assert plan.added == ["figures"]


# --- uploading --------------------------------------------------------------------------------
def _csrf_page() -> str:
    return '<html><meta name="ol-csrfToken" content="tok-project"></html>'


def _sent_body(registered: responses.BaseResponse) -> bytes:
    """The first request body a registered `responses` mock received, as bytes."""
    body = registered.calls[0].request.body
    if body is None:
        return b""
    return body if isinstance(body, bytes) else str(body).encode()


@responses.activate
def test_upload_sends_the_relative_path_and_csrf(tree, jar):
    responses.get(_url(f"/project/{PROJECT_ID}"), body=_csrf_page())
    upload = responses.post(
        _url(f"/project/{PROJECT_ID}/upload"),
        json={"success": True, "entity_id": "f9", "entity_type": "file"},
    )
    result = overleaf.upload_file(jar, PROJECT_ID, tree, "figures/new.png", b"\x89PNG")
    assert result.entity_id == "f9"
    request = upload.calls[0].request
    assert request.headers["x-csrf-token"] == "tok-project"
    assert f"folder_id={ROOT_FOLDER_ID}" in (request.url or "")
    body = _sent_body(upload)
    assert b'name="relativePath"\r\n\r\nfigures/new.png' in body
    assert b'name="qqfile"; filename="new.png"' in body


@responses.activate
def test_upload_at_the_root_sends_the_null_relative_path(tree, jar):
    responses.get(_url(f"/project/{PROJECT_ID}"), body=_csrf_page())
    upload = responses.post(
        _url(f"/project/{PROJECT_ID}/upload"),
        json={"success": True, "entity_id": "d9", "entity_type": "doc"},
    )
    overleaf.upload_file(jar, PROJECT_ID, tree, "main.tex", b"\\documentclass{article}")
    assert b'name="relativePath"\r\n\r\nnull' in _sent_body(upload)


@responses.activate
def test_upload_refusal_is_reported(tree, jar, capsys):
    responses.get(_url(f"/project/{PROJECT_ID}"), body=_csrf_page())
    responses.post(
        _url(f"/project/{PROJECT_ID}/upload"), json={"success": False, "error": "invalid_filename"}
    )
    with pytest.raises(typer.Exit):
        overleaf.upload_file(jar, PROJECT_ID, tree, "bad<name>.tex", b"x")
    assert "invalid_filename" in capsys.readouterr().err


@responses.activate
def test_delete_uses_the_entity_kind_route(jar):
    responses.get(_url(f"/project/{PROJECT_ID}"), body=_csrf_page())
    deletion = responses.delete(_url(f"/project/{PROJECT_ID}/folder/fold1"), status=204)
    overleaf.delete_entity(
        jar, PROJECT_ID, overleaf.RemoteEntity(path="figures", id="fold1", kind="folder")
    )
    assert deletion.call_count == 1


# --- compile ----------------------------------------------------------------------------------
def _compile_result(status: str = "success") -> overleaf.CompileResult:
    return overleaf.CompileResult.model_validate(
        {
            "status": status,
            "clsiServerId": "clsi-7",
            "outputFiles": [
                {"path": "output.pdf", "url": "/build/output.pdf", "build": "b1"},
                {"path": "output.log", "url": "/build/output.log", "build": "b1"},
            ],
        }
    )


def test_compile_result_picks_artefacts_by_suffix():
    result = _compile_result()
    pdf = result.artefact(".pdf")
    log = result.artefact(".log")
    assert pdf is not None and pdf.url == "/build/output.pdf"
    assert log is not None and log.url == "/build/output.log"
    assert result.artefact(".synctex.gz") is None


@responses.activate
def test_save_pdf_writes_the_artefact(jar, tmp_path):
    fetch = responses.get(_url("/build/output.pdf"), body=b"%PDF-1.5")
    dest = tmp_path / "paper.pdf"
    overleaf._save_pdf(jar, _compile_result(), dest)
    assert dest.read_bytes() == b"%PDF-1.5"
    # The backend pin the editor sends with every artefact fetch.
    assert "clsiserverid=clsi-7" in (fetch.calls[0].request.url or "")


def test_save_pdf_refuses_when_the_compile_made_none(jar, tmp_path, capsys):
    empty = overleaf.CompileResult.model_validate({"status": "failure", "outputFiles": []})
    with pytest.raises(typer.Exit) as caught:
        overleaf._save_pdf(jar, empty, tmp_path / "paper.pdf")
    assert caught.value.exit_code == 1
    assert "--logs" in capsys.readouterr().err


def test_compile_request_carries_the_editor_defaults():
    assert overleaf.CompileReq().model_dump() == {
        "draft": False,
        "check": "silent",
        "incrementalCompilesEnabled": True,
    }


# --- models -----------------------------------------------------------------------------------
def test_project_url_and_label_fall_back_to_the_id():
    project = overleaf.OverleafProject(id=PROJECT_ID)
    assert project.url == f"https://www.overleaf.com/project/{PROJECT_ID}"
    assert project.label == PROJECT_ID


def test_user_label_falls_back_to_the_name():
    assert overleaf.OverleafUser(firstName="Daniel", lastName="Hails").label == "Daniel Hails"
    assert overleaf.OverleafUser().label == "?"


def test_entities_are_hashable_so_plans_can_hold_them():
    entity = overleaf.RemoteEntity(path="main.tex", id="d1", kind="doc")
    assert {entity, entity} == {entity}


def test_cookie_jar_is_a_real_jar(jar):
    assert isinstance(jar, http.cookiejar.CookieJar)

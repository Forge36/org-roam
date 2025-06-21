;;; org-roam.el --- A database abstraction layer for Org-mode -*- coding: utf-8; lexical-binding: t; -*-

;; Copyright © 2020-2025 Jethro Kuan <jethrokuan95@gmail.com>

;; Author: Jethro Kuan <jethrokuan95@gmail.com>
;; URL: https://github.com/org-roam/org-roam
;; Keywords: org-mode, roam, convenience
;; Version: 2.3.0
;; Package-Requires: ((emacs "26.1") (dash "2.13") (org "9.6") (emacsql "4.1.0") (magit-section "3.0.0"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Org-roam is a Roam Research inspired Emacs package and is an addition to
;; Org-mode to have a way to quickly process complex SQL-like queries over a
;; large set of plain text Org-mode files. To achieve this Org-roam provides a
;; database abstraction layer, the capabilities of which include, but are not
;; limited to:
;;
;; - Link graph traversal and visualization.
;; - Instantaneous SQL-like queries on headlines
;;   - What are my TODOs, scheduled for X, or due by Y?
;; - Accessing the properties of a node, such as its tags, refs, TODO state or
;;   priority.
;;
;; All of these functionality is powered by this layer. Hence, at its core
;; Org-roam's primary goal is to provide a resilient dual representation of
;; what's already available in plain text, while cached in a binary database,
;; that is cheap to maintain, easy to understand, and is as up-to-date as it
;; possibly can. For users who would like to perform arbitrary programmatic
;; queries on their Org files Org-roam also exposes an API to this database
;; abstraction layer.
;;
;; -----------------------------------------------------------------------------
;;
;; In order for the package to correctly work through your interactive session
;; it's mandatory to add somewhere to your configuration the next form:
;;
;;     (org-roam-db-autosync-mode)
;;
;; The form can be called both, before or after loading the package, which is up
;; to your preferences. If you call this before the package is loaded, then it
;; will automatically load the package.
;;
;; -----------------------------------------------------------------------------
;;
;; This package also comes with a set of officially supported extensions that
;; provide extra features. You can find them in the "extensions/" subdirectory.
;; These extensions are not automatically loaded with `org-roam`, but they still
;; will be lazy-loaded through their own `autoload's.
;;
;; Org-roam also has other extensions that don't come together with this package.
;; Such extensions are distributed as their own packages, while also
;; authored and maintained by different people on distinct repositories. The
;; majority of them can be found at https://github.com/org-roam and MELPA.
;;
;;; Code:
(require 'dash)

(require 'rx)
(require 'seq)
(require 'cl-lib)

(require 'magit-section)

(require 'emacsql)
;; REVIEW: is this require needed?
;; emacsql-sqlite provides a common interface to an emacsql SQLite backend (e.g. emacs-sqlite-builtin)
;; not to be confused with a backend itself named emacsql-sqlite that existed in emacsql < 4.0.
(require 'emacsql-sqlite)

(require 'org)
(require 'org-id)
(require 'ol)
(require 'org-element)
(require 'org-capture)
(require 'org-roam-lib)

(require 'ansi-color) ; to strip ANSI color codes in `org-roam--list-files'

(eval-when-compile
  (require 'subr-x))

;;; Library

(declare-function org-roam-descendant-of-p "org-roam-utils")

(defun org-roam-file-p (&optional file)
  "Return t if FILE is an Org-roam file, nil otherwise.
If FILE is not specified, use the current buffer's file-path.

FILE is an Org-roam file if:
- It's located somewhere under `org-roam-directory'
- It has a matching file extension (`org-roam-file-extensions')
- It doesn't match excluded regexp (`org-roam-file-exclude-regexp')"
  (when (or file (buffer-file-name (buffer-base-buffer)))
    (let* ((path (or file (buffer-file-name (buffer-base-buffer))))
           (relative-path (file-relative-name path org-roam-directory))
           (ext (org-roam--file-name-extension path))
           (ext (if (or (string= ext "gpg")
                        (string= ext "age"))
                    (org-roam--file-name-extension (file-name-sans-extension path))
                  ext))
           (org-roam-dir-p (org-roam-descendant-of-p path org-roam-directory))
           (valid-file-ext-p (member ext org-roam-file-extensions))
           (match-exclude-regexp-p
            (cond
             ((not org-roam-file-exclude-regexp) nil)
             ((stringp org-roam-file-exclude-regexp)
              (string-match-p org-roam-file-exclude-regexp relative-path))
             ((listp org-roam-file-exclude-regexp)
              (let (is-match)
                (dolist (exclude-re org-roam-file-exclude-regexp)
                  (setq is-match (or is-match (string-match-p exclude-re relative-path))))
                is-match)))))
      (save-match-data
        (and
         path
         org-roam-dir-p
         valid-file-ext-p
         (not match-exclude-regexp-p))))))

;;;###autoload
(defun org-roam-list-files ()
  "Return a list of all Org-roam files under `org-roam-directory'.
See `org-roam-file-p' for how each file is determined to be as
part of Org-Roam."
  (org-roam--list-files (expand-file-name org-roam-directory)))

(defun org-roam-buffer-p (&optional buffer)
  "Return t if BUFFER is for an Org-roam file.
If BUFFER is not specified, use the current buffer."
  (let ((buffer (or buffer (current-buffer)))
        path)
    (with-current-buffer buffer
      (and (derived-mode-p 'org-mode)
           (setq path (buffer-file-name (buffer-base-buffer)))
           (org-roam-file-p path)))))

(defun org-roam-buffer-list ()
  "Return a list of buffers that are Org-roam files."
  (--filter (org-roam-buffer-p it)
            (buffer-list)))

(defun org-roam--file-name-extension (filename)
  "Return file name extension for FILENAME.
Like `file-name-extension', but does not strip version number."
  (save-match-data
    (let ((file (file-name-nondirectory filename)))
      (if (and (string-match "\\.[^.]*\\'" file)
               (not (eq 0 (match-beginning 0))))
          (substring file (+ (match-beginning 0) 1))))))

(defun org-roam--list-files (dir)
  "Return all Org-roam files located recursively within DIR.
Use external shell commands if defined in `org-roam-list-files-commands'."
  (let (path exe)
    (cl-dolist (cmd org-roam-list-files-commands)
      (pcase cmd
        (`(,e . ,path)
         (setq path (executable-find path)
               exe  (symbol-name e)))
        ((pred symbolp)
         (setq path (executable-find (symbol-name cmd))
               exe (symbol-name cmd)))
        (wrong-type
         (signal 'wrong-type-argument
                 `((consp symbolp)
                   ,wrong-type))))
      (when path (cl-return)))
    (if-let* ((files (when path
                       (let ((fn (intern (concat "org-roam--list-files-" exe))))
                         (unless (fboundp fn) (user-error "%s is not an implemented search method" fn))
                         (funcall fn path (format "\"%s\"" dir)))))
              (files (seq-filter #'org-roam-file-p files))
              (files (mapcar #'expand-file-name files))) ; canonicalize names
        files
      (org-roam--list-files-elisp dir))))

(defun org-roam--shell-command-files (cmd)
  "Run CMD in the shell and return a list of files.
If no files are found, an empty list is returned."
  (--> cmd
       (shell-command-to-string it)
       (ansi-color-filter-apply it)
       (split-string it "\n")
       (seq-filter (lambda (s)
                     (not (or (null s) (string= "" s)))) it)))

(defun org-roam--list-files-search-globs (exts)
  "Given EXTS, return a list of search globs.
E.g. (\".org\") => (\"*.org\" \"*.org.gpg\")"
  (cl-loop for e in exts
           append (list (format "\"*.%s\"" e)
                        (format "\"*.%s.gpg\"" e)
                        (format "\"*.%s.age\"" e))))

(defun org-roam--list-files-find (executable dir)
  "Return all Org-roam files under DIR, using \"find\", provided as EXECUTABLE."
  (let* ((globs (org-roam--list-files-search-globs org-roam-file-extensions))
         (names (string-join (mapcar (lambda (glob) (concat "-name " glob)) globs) " -o "))
         (command (string-join `(,executable "-L" ,dir "-type f \\(" ,names "\\)") " ")))
    (org-roam--shell-command-files command)))

(defun org-roam--list-files-fd (executable dir)
  "Return all Org-roam files under DIR, using \"fd\", provided as EXECUTABLE."
  (let* ((globs (org-roam--list-files-search-globs org-roam-file-extensions))
         (extensions (string-join (mapcar (lambda (glob) (concat "-e " (substring glob 2 -1))) globs) " "))
         (command (string-join `(,executable "-L" "--type file" ,extensions "." ,dir) " ")))
    (org-roam--shell-command-files command)))

(defalias 'org-roam--list-files-fdfind #'org-roam--list-files-fd)

(defun org-roam--list-files-rg (executable dir)
  "Return all Org-roam files under DIR, using \"rg\", provided as EXECUTABLE."
  (let* ((globs (org-roam--list-files-search-globs org-roam-file-extensions))
         (command (string-join `(
                                 ,executable "-L" ,dir "--files"
                                 ,@(mapcar (lambda (glob) (concat "-g " glob)) globs)) " ")))
    (org-roam--shell-command-files command)))

(declare-function org-roam--directory-files-recursively "org-roam-compat")

(defun org-roam--list-files-elisp (dir)
  "Return all Org-roam files under DIR, using Elisp based implementation."
  (let ((regex (concat "\\.\\(?:"(mapconcat
                                  #'regexp-quote org-roam-file-extensions
                                  "\\|" )"\\)\\(?:\\.gpg\\|\\.age\\)?\\'"))
        result)
    (dolist (file (org-roam--directory-files-recursively dir regex nil nil t) result)
      (when (and (file-readable-p file)
                 (org-roam-file-p file))
        (push file result)))))

;;; Package bootstrap
(provide 'org-roam)

(cl-eval-when (load eval)
  (require 'org-roam-compat)
  (require 'org-roam-utils)
  (require 'org-roam-db)
  (require 'org-roam-node)
  (require 'org-roam-id)
  (require 'org-roam-capture)
  (require 'org-roam-mode)
  (require 'org-roam-log)
  (require 'org-roam-migrate)
  (require 'org-roam-vars))

;;; org-roam.el ends here

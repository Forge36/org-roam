;;; org-roam-lib.el --- core variables and APIs used by org-roam -*- lexical-binding: t; -*-

;; Copyright © 2020-2025 Jethro Kuan <jethrokuan95@gmail.com>

;; Author: Jethro Kuan <jethrokuan95@gmail.com>
;; URL: https://github.com/org-roam/org-roam
;; Keywords: org-mode, roam, convenience, vars
;; Version: 2.3.0
;; Package-Requires: ((emacs "26.1") (dash "2.13") (org "9.6") (magit-section "3.0.0"))

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
;; This module is dedicated for Org-roam variables and function
;; declartions. It provides a bare-bones definitions to allow
;; importing in all other modules to avoid byte-compile warnings
;; and circular references.
;;

;;; Code:
(require 'org-attach)                   ; To set `org-attach-id-dir'

;;; Lib:
(declare-function org-roam-list-files "org-roam")

;;; Options:
(defgroup org-roam nil
  "A database abstraction layer for Org-mode."
  :group 'org
  :prefix "org-roam-"
  :link '(url-link :tag "Github" "https://github.com/org-roam/org-roam")
  :link '(url-link :tag "Online Manual" "https://www.orgroam.com/manual.html"))

(defcustom org-roam-directory nil
  "The directory that will contain your notes. Org-roam will search
recursively within for notes. This variable needs to be set before any
calls to Org-roam functions."
  :group 'org-roam
  :type 'string)

(defgroup org-roam-faces nil
  "Faces used by Org-roam."
  :group 'org-roam
  :group 'faces)

(defcustom org-roam-verbose t
  "Echo messages that are not errors."
  :type 'boolean
  :group 'org-roam)

(defcustom org-roam-directory (expand-file-name "~/org-roam/")
  "Default path to Org-roam files.
All Org files, at any level of nesting, are considered part of the Org-roam."
  :type 'directory
  :group 'org-roam)

(defcustom org-roam-find-file-hook nil
  "Hook run when an Org-roam file is visited."
  :group 'org-roam
  :type 'hook)

(defcustom org-roam-post-node-insert-hook nil
  "Hook run when an Org-roam node is inserted as an Org link.
Each function takes two arguments: the id of the node, and the link description."
  :group 'org-roam
  :type 'hook)

(defcustom org-roam-file-extensions '("org")
  "List of file extensions to be included by Org-Roam.
While a file extension different from \".org\" may be used, the
file still needs to be an `org-mode' file, and it is the user's
responsibility to ensure that."
  :type '(repeat string)
  :group 'org-roam)

(defcustom org-roam-file-exclude-regexp (list org-attach-id-dir)
  "Files matching this regular expression or list of regular expressions
are excluded from the Org-roam."
  :type '(choice
          (repeat
           (string :tag "Regular expression matching files to ignore"))
          (string :tag "Regular expression matching files to ignore")
          (const :tag "Include everything" nil))
  :group 'org-roam)

(defcustom org-roam-list-files-commands
  (if (member system-type '(windows-nt ms-dos cygwin))
      nil
    '(find fd fdfind rg))
  "Commands that will be used to find Org-roam files.

It should be a list of symbols or cons cells representing any of
the following supported file search methods.

The commands will be tried in order until an executable for a
command is found. The Elisp implementation is used if no command
in the list is found.

  `find'

    Use find as the file search method.
    Example command:
      find /path/to/dir -type f \
        \( -name \"*.org\" -o -name \"*.org.gpg\" -name \"*.org.age\" \)

  `fd'

    Use fd as the file search method.
    Example command:
      fd /path/to/dir/ --type file -e \".org\" -e \".org.gpg\" -e \".org.age\"

  `fdfind'

    Same as `fd'. It's an alias that used in some OSes (e.g. Debian, Ubuntu)

  `rg'

    Use ripgrep as the file search method.
    Example command:
       rg /path/to/dir/ --files -g \"*.org\" -g \"*.org.gpg\" -g \"*.org.age\"

By default, `executable-find' will be used to look up the path to
the executable. If a custom path is required, it can be specified
together with the method symbol as a cons cell. For example:
\\='(find (rg . \"/path/to/rg\"))."
  :type '(set
          (const :tag "find" find)
          (const :tag "fd" fd)
          (const :tag "fdfind" fdfind)
          (const :tag "rg" rg)
          (const :tag "elisp" nil)))

(defcustom org-roam-directory nil
  "The directory that will contain your notes. Org-roam will search
recursively within for notes. This variable needs to be set before any
calls to Org-roam functions."
  :group 'org-roam
  :type 'string)

(defvar org-roam-node-point nil
  "Stores current capture node.")

(provide 'org-roam-lib)

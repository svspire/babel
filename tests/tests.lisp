;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; tests.lisp --- Unit and regression tests for Babel.
;;;
;;; Copyright (C) 2007, Luis Oliveira  <loliveira@common-lisp.net>
;;;
;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use, copy,
;;; modify, merge, publish, distribute, sublicense, and/or sell copies
;;; of the Software, and to permit persons to whom the Software is
;;; furnished to do so, subject to the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;;; DEALINGS IN THE SOFTWARE.

(in-package #:cl-user)

(defpackage #:babel-tests
  (:use #:common-lisp #:babel #:babel-encodings #:rtest))
(in-package #:babel-tests)

(defun ub8v (&rest contents)
  (make-array (length contents) :element-type '(unsigned-byte 8)
              :initial-contents contents))

;;;; Simple tests using ASCII

(deftest enc.ascii.1
    (string-to-octets "abc" :encoding :ascii)
  #(97 98 99))

(deftest enc.ascii.2
    (string-to-octets (string #\uED) :encoding :ascii :errorp nil)
  #(#x1a))

(deftest enc.ascii.3
    (handler-case
        (string-to-octets (string #\uED) :encoding :ascii :errorp t)
      (character-encoding-error (c)
        (values
         (character-coding-error-position c)
         (character-coding-error-encoding c)
         (character-encoding-error-code c))))
  0 :ascii #xed)

(deftest dec.ascii.1
    (octets-to-string (ub8v 97 98 99) :encoding :ascii)
  "abc")

(deftest dec.ascii.2
    (handler-case
        (octets-to-string (ub8v 97 128 99) :encoding :ascii :errorp t)
      (character-decoding-error (c)
        (values
         (character-decoding-error-octets c)
         (character-coding-error-position c)
         (character-coding-error-encoding c))))
  #(128) 1 :ascii)

(deftest dec.ascii.3
    (octets-to-string (ub8v 97 255 98 99) :encoding :ascii :errorp nil)
  #(#\a #\Sub #\b #\c))

(deftest oct-count.ascii.1
    (string-size-in-octets "abc" :encoding :ascii)
  3 3)

(deftest char-count.ascii.1
    (vector-size-in-chars (ub8v 97 98 99) :encoding :ascii)
  3 3)

;;;; UTF-8

;;; TODO: test with more invalid UTF-8 sequences.

(deftest char-count.utf-8.1
    ;; "ni hao" in hanzi with the last octet missing
    (vector-size-in-chars (ub8v 228 189 160 229 165) :errorp nil)
  1 3)

(deftest char-count.utf-8.2
    ;; same as above with the last 2 octets missing
    (handler-case
        (vector-size-in-chars (ub8v 228 189 160 229) :errorp t)
      (end-of-input-in-character (c)
         (values
          (character-decoding-error-octets c)
          (character-coding-error-position c)
          (character-coding-error-encoding c))))
  #(229) 3 :utf-8)

;;; Lispworks bug?
#+lispworks
(pushnew 'dec.utf-8.1 rtest::*expected-failures*)

(deftest dec.utf-8.1
    (string= (octets-to-string (ub8v 228 189 160 229) :errorp nil)
             (string #\u4f60))
  t)

(deftest dec.utf-8.2
    (handler-case
        (octets-to-string (ub8v 228 189 160 229) :errorp t)
      (end-of-input-in-character (c)
        (values
         (character-decoding-error-octets c)
         (character-coding-error-position c)
         (character-coding-error-encoding c))))
  #(229) 3 :utf-8)

;;;; UTF-16

;;; Test that the BOM is not being counted as a character.
(deftest char-count.utf-16.1
    (values
     (vector-size-in-chars (ub8v #xfe #xff #x00 #x55 #x00 #x54 #x00 #x46)
                           :encoding :utf-16)
     (vector-size-in-chars (ub8v #xff #xfe #x00 #x55 #x00 #x54 #x00 #x46)
                           :encoding :utf-16))
  3 3)

;;;; MORE TESTS

(defparameter *standard-characters*
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!$\"'(),_-./:;?+<=>#%&*@[\\]{|}`^~")

;;; Testing consistency by encoding and decoding a simple string for
;;; all character encodings.
(deftest rw-equiv.1
    (let (failed)
      (dolist (*default-character-encoding* (list-character-encodings) failed)
        (let ((octets (string-to-octets *standard-characters*)))
          (unless (string= (octets-to-string octets) *standard-characters*)
            (push *default-character-encoding* failed)))))
  nil)

;;; Testing against files generated by GNU iconv.

(defun test-file (name type)
  (let ((sys-pn (asdf:system-definition-pathname
                 (asdf:find-system 'babel-tests))))
    (make-pathname :name name :type type
                   :directory (append (pathname-directory sys-pn)
                                      '("tests"))
                   :defaults sys-pn)))

(defun read-test-file (name type)
  (with-open-file (in (test-file name type) :element-type '(unsigned-byte 8))
    (let* ((data (loop for byte = (read-byte in nil nil)
                       until (null byte) collect byte)))
      (make-array (length data) :element-type '(unsigned-byte 8)
                  :initial-contents data))))

(defun test-encoding (enc)
  (let* ((*default-character-encoding* enc)
         (enc-name (string-downcase (symbol-name enc)))
         (utf8-octets (read-test-file enc-name "txt-utf8"))
         (foo-octets (read-test-file enc-name "txt"))
         (utf8-string (octets-to-string utf8-octets :encoding :utf-8 :errorp t))
         (foo-string (octets-to-string foo-octets :errorp t)))
    (assert (string= utf8-string foo-string))
    (assert (= (length foo-string) (vector-size-in-chars foo-octets :errorp t)))
    (unless (member enc '(:utf-16 :utf-32))
      ;; FIXME: skipping UTF-16 and UTF-32 because of the BOMs and
      ;; because the input might not be in native-endian order so the
      ;; comparison will fail there.
      (let ((new-octets (string-to-octets foo-string :errorp t)))
        (assert (equalp new-octets foo-octets))
        (assert (= (length foo-octets)
                   (string-size-in-octets foo-string :errorp t)))))))

(deftest iconv-test
    (let (failed)
      (format t "~&;;~%;; testing all supported encodings:~%;;~%")
      (dolist (enc (list-character-encodings))
        (format t "~&;;   ~A ... " enc)
        (handler-case
            (progn
              (test-encoding enc)
              (format t "OK~%"))
          ;; run TEST-ENCODING manually to have a look at the error
          (error ()
            (push enc failed)
            (format t "FAILED~%"))))
      (format t "~&;;~%")
      failed)
  nil)

;;; RT: accept encoding objects in LOOKUP-MAPPING etc.
(deftest encoding-objects.1
    (string-to-octets "abc" :encoding (get-character-encoding :ascii))
  #(97 98 99))

(deftest sharp-backslash.1
    (loop for string in '("#\\a" "#\\u" "#\\ued")
          collect (char-code (read-from-string string)))
  (97 117 #xed))

(deftest sharp-backslash.2
    (handler-case (read-from-string "#\\u12zz")
      (reader-error () 'reader-error))
  reader-error)

;;; RT: the slow implementation of with-simple-vector was buggy.
(deftest string-to-octets.1
    (code-char (aref (string-to-octets "abc" :start 1 :end 2) 0))
  #\b)

(deftest simple-base-string.1
    (string-to-octets (coerce "abc" 'base-string) :encoding :ascii)
  #(97 98 99))

(deftest utf-8b.1
    (string-to-octets (coerce #(#\a #\b #\udcf0) 'string) :encoding :utf-8b)
  #(97 98 #xf0))

(deftest utf-8b.2
    (octets-to-string (ub8v 97 98 #xcd) :encoding :utf-8b)
  #(#\a #\b #\udccd))

(deftest utf-8b.3
    (octets-to-string (ub8v 97 #xf0 #xf1 #xff #x01) :encoding :utf-8b)
  #(#\a #\udcf0 #\udcf1 #\udcff #\udc01))

(deftest utf-8b.4
    (let* ((octets (coerce (loop repeat 8192 collect (random (+ #x82)))
                           '(array (unsigned-byte 8) (*))))
           (string (octets-to-string octets :encoding :utf-8b)))
      (equalp octets (string-to-octets string :encoding :utf-8b)))
  t)

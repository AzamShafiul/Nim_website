import db_sqlite # SQLite
import jester # Our webserver
import logging # Logging utils
import os, math # Used to get arguments
import parsecfg # Parse CFG (config) files
import strutils, sequtils, json # Basic functions
import times # Time and date
import uri, random, argon2, md5, validator # We need to encode urls: encodeUrl()
var db: DbConn
var loggedin* = false
var name*: string
var balance*: int
var userid*: int
db = open("bank.db", "", "", "")
include "tmpl/main.tmpl"
include "tmpl/register.nim"
proc makeSalt*(arguments: int): string =
    result = ""
    for i in 0..arguments:
        result.add(chr(rand(94) + 32)) # Generate numbers from 32 to 94 + 32 = 126
proc makePassword*(password, salt: string): string =
    ## Creates an MD5 hash by combining password and salt
    result = argon2(getMD5(getMD5(password)), salt).enc

proc register(name, email: string, password: string,
        confirmpass: string): string =
    echo email, password
    var count = 0
    var errorName, errorEmail, errorPass, errorCpass: string
    if name.len < 1:
        errorName = "Name is not given"
        count = count+1
    if email.len < 1:
        errorEmail = "Email is not given"
        count = count+1
    else:
        if not isEmail(email):
            errorEmail = "Not an Email"
            if password.len < 1:
                errorEmail = "Password is not given"
                count = count+1
    if password.len < 6:
        errorPass = "Password is less than six"
        count = count+1
    if confirmpass.len < 1:
        errorCpass = "Confirm password is not given"
    if password == confirmpass:
        errorCpass = "Confirm password is not matched with password"
        count = count+1
    if count > 0:
        let jsonObject = %* {"errorName": errorName, "errorEmail": errorEmail,
                "errorPass": errorPass, "errorCpass": errorCpass}
        return($jsonObject)

    db.exec(sql"""CREATE TABLE IF NOT EXISTS user (
  "id"	INTEGER NOT NULL,
  "name"	TEXT NOT NULL,
	"email"	TEXT NOT NULL UNIQUE,
  "password"	TEXT NOT NULL,
  "salt" TEXT NOT NULL,
	"balance"	INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY("id")
              )""")
    let salt = makeSalt(8)
    var pwd = makePassword(password, salt)


    db.exec(sql"INSERT INTO user (name, email,password,salt) VALUES (?, ?, ?,?)",
            name, email, pwd, salt)
    for row in db.fastRows(sql"SELECT * FROM user"):
        echo row
    return("")
proc login(email, password: string): tuple[ee: string, s: string] =
    var count = 0
    var errorEmail, errorPass: string

    if email.len < 1:
        errorEmail = "Email is not given"
        count = count+1
    else:
        if not isEmail(email):
            errorEmail = "Not an Email"
    if password.len < 6:
        errorPass = "Password is less than six"
        count = count+1
    if count > 0:
        let jsonObject = %* {"errorEmail": errorEmail, "errorPass": errorPass}
        return($jsonObject, "")
    var salt = db.getValue(sql"SELECT salt FROM user where  email =?", email)
    echo salt
    for row in db.fastRows(sql"SELECT * FROM user"):
        echo row

    var pwd = makePassword(password, salt)
    var key = makeSalt(12)
    for row in db.fastRows(sql"SELECT * FROM user where email =? and password =?",
            email, pwd):
        echo row

        db.exec(sql"""CREATE TABLE IF NOT EXISTS session (
          id integer,
          key text not null,
          userid integer not null,
          foreign key (userid) references user(id)
	PRIMARY KEY("id")
                  )""")

        db.exec(sql"INSERT INTO session (key,userid) VALUES (?,?)", key, row[0])
    for row in db.fastRows(sql"SELECT * FROM session "):
        echo row
        userid = parseInt(row[0])
    return ("", key)

proc logout(request: object) =
    name = ""

    db.exec(sql"DELETE FROM session WHERE  key = ?", request.cookies["sid"])
    loggedin = false

proc checkCookie(req: object) =
    if not req.cookies.hasKey("sid"): return
    let sid = req.cookies["sid"]
    var userid = db.getValue(sql"SELECT userid FROM session where key =?", sid)
    if db.tryExec(sql"SELECT * FROM user where id =?", userid):
        for row in db.fastRows(sql"SELECT * FROM user where id =?", userid):
            loggedin = true
            name = row[1]
            balance = parseInt(row[5])
    else:
        loggedin = false

proc show() =
    if db.tryExec(sql"SELECT * FROM user"):
        for row in db.fastRows(sql"SELECT * FROM user"):
            echo row
    if db.tryExec(sql"SELECT * FROM session"):
        for row in db.fastRows(sql"SELECT * FROM session"):
            echo row


    if db.tryExec(sql"SELECT * FROM transactionn where id =?", userid):
        for row in db.fastRows(sql"SELECT * FROM transactionn where id =?", userid):
            echo row
proc transaction(typee: string, amount: int) =
    var bal: int
    db.exec(sql"""CREATE TABLE IF NOT EXISTS transactionn (
          id integer not null,
          userid integer not null,
          type text not null,
          amount integer not null,
          date not null default (STRFTIME('%Y-%m-%d','now')),
          time not null default (STRFTIME('%H:%M:%S','now')),
          foreign key (userid) references user(id)
	PRIMARY KEY("id")
                  )""")
    db.exec(sql"INSERT INTO transactionn (userid,type,amount) VALUES (?, ?, ?)",
            userid, typee, amount)
    if(typee == "debit"):
        bal = balance - amount

    if(typee == "credit"):
        bal = balance + amount

    if db.tryExec(sql"Update user set balance =? where id =?", bal, userid):
        if db.tryExec(sql"SELECT * FROM user"):
            for row in db.fastRows(sql"SELECT * FROM user"):
                echo row
routes:
    get "/":
        checkCookie(request)
        if(loggedin):
            resp genUser()
        else:
            resp genMain()

    get "/register":
        resp genRegs("")

    get "/login":

        resp genLog("")



    get "/show":
        show()
        resp ""

    get "/logout":
        logout(request)
        redirect("/")

    get "/transactionForm":
        if(loggedin):
            resp genTran()
        else:
            resp"To make transaction you should be logged in"

    get "/transactions":

        if(loggedin):
            resp genTransactions()
        else:
            resp"To see transaction you should be logged in"

    post "/transaction":
        if(loggedin):
            transaction((@"type"), parseInt((@"amount")))
            redirect("/")
        else:
            resp"To make transaction you should be logged in"

    post "/login":
        if(name.len > 0):
            resp"You are already logged in"
        let (error, sid) = login((@"email"), (@"pwd"))
        if(sid.len > 0):
            jester.setCookie("sid", sid, daysForward(7))
            redirect("/")
        resp genLog(error)


    post "/register":
        let error = register((@"name"), (@"email"), (@"pwd"), (@"cpwd"))
        if error.len > 0:
            resp genRegs(error)
        resp"You are registered"

        redirect("http://127.0.0.1:5000/")


#discard genReg()

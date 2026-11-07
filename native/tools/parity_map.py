"""Second half of the parity mappings (imported by gen_parity.py).

MAP_ACTIONS: original action id -> (native name, engine function or screen). The status is worked out by gen_parity.py:
"Engine + screen" when the app sources call the engine function, "Engine only" when they do not, "Ported" for screen-only
items that need no engine call.
MISSING: area -> text with one "id description" per line. Every original action that is not mapped must be in exactly one area.
"""

# id: engine function (name searched for in App/ to decide Engine + screen / Engine only)
MAP_ACTIONS = {
 # startups, funding, private equity, owners, listing (Events/Startups, Funding, PrivateEquity, Shareholders, BigMeeting)
 "f17go": "foundStartup", "f17model": "foundStartup", "f17sec": "foundStartup", "f17seed": "foundStartup", "f17who": "foundStartup", "p17open": "rivalTargetsForProduct", "p17go": "pitchProductToRival", "w17dev": "changeBuilders", "w17self": "toggleOwnerHoursOnProduct", "w17use": "toggleProductUse", "w17int": "setProductInternalPrice", "sudeal": "investInStartup", "sugo": "investInStartup", "suhelp": "helpStartupOnBoard", "susell": "sellStartupStake", "pitch": "pitchToInvestors", "fundacc": "acceptFundingOffer", "fundctr": "counterFundingOffer", "funddec": "declineFundingOffer", "fpitch": "pitchStartupRound", "facc": "acceptStartupRound", "fdec": "declineStartupRound", "ftop": "putMoneyIntoStartup", "ftopgo": "putMoneyIntoStartup", "fshut": "shutDownStartup", "bigacc": "acceptBigMeetingOffer", "bigctr": "counterBigMeetingOffer", "bigwalk": "walkAwayFromBigMeeting", "salepct": "listSharesForSale", "sellsh": "sellPrivateShares", "own27pol": "setDividendPolicy", "own27buy": "buyBackStake", "pe56go": "commitToFund", "pe56sell": "sellFundStake", "hlist": "listHoldingOnExchange", "hraise": "raiseMoneyForHolding", "nhpub": "listHoldingOnExchange", "saleq": "askBuyer", "saletalk": "counterBuyer", "saletab": "listSharesForSale", "salemode": "listSharesForSale", "stab": "foundedStartups",
 # selling a company (Events/CompanySale)
 "salego": "CompanySale.startListing", "salectr": "CompanySale.counter", "salecounter": "CompanySale.counter",
 "saledec": "CompanySale.decline", "saledec7": "CompanySale.decline", "salewd": "CompanySale.withdraw",
 "saleacc": "CompanySale.accept", "sellco": "CompanySale.accept",
 # hiring and staff
 "offer": "hire", "offer7": "hire", "pay7": "hire", "mkt26hire": "hire", "mkt26rep": "orderMarketReport", "arep": "orderAnalystReport",
 # world around you, ranking, own software, key accounts, IT security (this branch)
 "rk27f": "rankingBoard", "rk27s": "rankingBoard", "st27": "rankingBoard", "fav31ask": "askForFavour", "fav31call": "callInFavour", "fav31keep": "keepPromise", "net31p": "peopleYouKnow",
 "swdev": "setSoftwareCoders", "swself": "setSoftwareSelfCoding", "swmodel": "setSoftwareModel", "swint": "setSoftwareInternalPercent", "ownsw": "useOwnSoftware",
 "acc39": "keyAccountProfile", "acc39d": "setAccountDiscount", "cy56set": "setCyberLevel", "cy56bk": "toggleBackups", "cy56tr": "trainStaff", "verifyag": "verifySalesperson",
 "onbtick": "completePaperwork", "raisesheet": "raise", "talkstaff": "raise", "refcheck": "checkManagerReferences",
 "msearch56": "searchManagers", "promogo": "offerPromotion", "promoboss": "offerPromotion",
 # money
 "buyasset": "buyInvestment", "trade": "buyInvestment", "sellasset": "sellInvestment", "depgo": "openDeposit",
 "trgo": "putMoneyInto", "perloan": "takeLoan", "ploanT": "takeLoan", "loansheet": "takeLoan", "loanterm": "takeLoan",
 "repaysheet": "repayLoan", "cofin": "takeLoan", "cash41in": "putMoneyInto", "cosal": "setOwnerSalary",
 "cosub": "subscribeSoftware", "buyveh": "buyVehicleItem",
 # company set-up and switches
 "docsall": "quickSetup", "autoset": "quickSetup", "ncset": "startCompany", "ncgo": "startCompany",
 "setcountry": "newGame", "setcity": "newGame", "age56": "newGame",
 "hysPick": "setKnob", "hysGo": "setKnob", "hysTog": "setKnob", "pm16set": "setPriceLevel", "pm16go": "setPriceLevel",
 "ch16rp": "setChainRule", "plset": "setCampaign", "plgo": "setCampaign", "plopen": "setCampaign",
 # franchise, holding, supply
 "brandpick": "franchiseBrand", "branduse": "startFranchisedCompany", "negstep": "negotiateFranchise",
 "frt56": "negotiateFranchise", "hrel": "releaseFromHolding", "nhgo": "createHolding", "ch27k": "setSupplier",
 # ported in this task (Simulation/MiscActions.swift)
 "rn56go": "renameCompany", "rb56go": "renameChain", "clgo": "closeCompany", "reopen": "reopenCompany",
 "winduo": "windUpCompany", "convgo": "convertToLimited", "ccheck": "setCreditCheck", "autostock": "setAutoStock",
 "inflset": "setInflationHold",
 # boards, team, office, meetings, academy (Simulation/ExecutiveActions.swift)
 "bd12mode": "setBoardMode",
 "bd12freq": "setBoardMode",
 "bd12rm": "removeFromBoard",
 "bd12find": "searchForSeat",
 "bd13find": "searchForSeat",
 "bd12inv": "fillSeat",
 "bd13hire": "fillSeat",
 "bd12meet": "holdBoardMeeting",
 "bd12yes": "decideMeetingItem",
 "bd12no": "decideMeetingItem",
 "emg12pick": "pickEmergency",
 "b12go": "boardVote",
 "b13go": "recordPushedThrough",
 "lh12set": "setRightHand",
 "lh12fire": "fireOffice",
 "ch12lend": "lendFromSister",
 "ch12fire": "releaseExecutive",
 "tm56fire": "releaseTeam",
 "tm56auth": "setTeamAuthority",
 "fireceo": "releaseGroupCEO",
 "fireregional": "releaseExecutive",
 "firehq": "fireOffice",
 "ceolvl": "setExecutiveAuthority",
 "ceobuy": "setExecutiveAuthority",
 "reglvl": "setExecutiveAuthority",
 "regbuy": "setExecutiveAuthority",
 "setbig": "setGroupLimit",
 "hqsearch": "searchOffice",
 "hqoffer": "hireOffice",
 "hqtick": "tickOfficePaperwork",
 "hqas": "toggleOfficeAssignment",
 "rentoffice": "rentOffice",
 "repset": "setReports",
 "perfauto": "setPerformanceAnalystAuto",
 "mtgo2": "meetForProposals",
 "tmgo": "callMeeting",
 "docourse": "sendOnCourse",
 "own27pol": "setDividendPolicy",
 "own27buy": "buyBackStake",
 "bigacc": "acceptBigOffer",
 "bigctr": "counterBigOffer",
 "bigwalk": "walkAwayFromBigOffer",
 "arep": "requestAnalystReport",
 "hqstep56": "searchOffice",
 # ported in the "other" pass (Businesses/StaffContracts, Development, PlayerGoals; Simulation/MiscActions)
 "ch12lend": "lendWorker", "trial": "startTrialWeek", "carallow": "toggleOwnCar", "carc": "Hiring.Terms", "car7": "Hiring.Terms",
 "pickacc": "changeAccountant", "pm16camp": "startDiscount", "pm16end": "endDiscount", "home37": "giveUpPremises", "complres": "answerComplaint",
 "stseas": "toggleSeason", "stpart": "offerPartTime", "stfix": "offerFixedSalary", "sthrs": "setStaffHours", "stfull": "offerFullTime",
 "setpay": "setPayModel", "setrate": "setCommissionRate", "pt48": "Hiring.Terms", "hk54k": "Hiring.Terms", "hk54b": "Hiring.Terms",
 "hk54h": "Hiring.Terms", "hk54s": "seasonMonths", "rd56go": "startDevelopment", "amb27pick": "chooseAmbition", "dy59claim": "claimDailyGoal",
 "fs58claim": "claimFirstStep", "fs58off": "setFirstStepsHidden",
}

# screen-only items that need no engine call (navigation, choosing, filtering, showing)
MAP_SCREEN_ACTIONS = {}

MISSING = {}

MISSING["boards"] = """
bk13ok Dismiss a board message from the queue
b14go Continue after a board popup (round 14)
md56 Set the duties a manager performs
md56give Give a manager a duty
tmset Set the options of a meeting with all managers
mtwho Choose who is called to a meeting
mtypeset Choose the type of a meeting
tg58set Set a target or budget for a manager
tg58f Set a field of the budget form
tg58go Approve the yearly budget with a manager
p11duty Set the duties of a promoted worker
acad36 Open the academy for a company
acadco Choose the company in the academy
acadc Choose a course category in the academy
acads Choose a course in the academy
coursesheet Open the sheet to book a course for a worker
hqref Check references of a head-office candidate
hirehq Hire a head-office worker
hqcandopen Open a head-office candidate
hqmode Choose the head-office search mode
hqtab Head-office tab
hq56t Head-office table tab
officepop Move the main office
reviewall Run a performance review of all managers
reviewnow Run a performance review of one manager
boarddeal Take a deal to the board
vmeet Open a meeting
cv56meet Open the meeting thread with a manager
"""

MISSING["startups"] = """
rfset Set the restructuring plan in a crisis
warnstaff Warn staff of layoffs in a crisis
loset Set the layoff plan
logo Carry out the layoffs
hfin Choose which holdings the finance manager covers
"""

MISSING["rivals"] = """
rm27 Answer a rival's counter move (match, ignore)
rivhow Absorb a rival (merge or shut)
rivmeet Meet a rival owner
rivbuy Buy a rival company
rivoffer Offer a price for a rival
rivclose Close a rival's business
rivfin27 Take an acquisition loan from your bank
riv31meet Meet a rival in the world around you
pwpick Choose the rival in a price war
pwlen Choose the length of a price war
pwgo Start a price war
pwgo7 Start a price war (round 7 form)
pwend End a price war
branchgo Open a branch next to a rival
ch39set Link a key account to a supplier
ch39off Remove a key-account link
acctmeet Meet a key account
acctdrop End a key-account contract
ct56 Open a contract with a business customer
sw33t Sales mechanics switch (upsell and similar)
rvf Reviews filter
rvmore Show more reviews
rvopen Open a review
sc56 Score card of a company
rv56 Open the reviews app for a company
"""

MISSING["advisers"] = """
abrset Set the abroad option for a company
abrgo Start a company abroad
toggleins Switch a business insurance policy on or off
fmhire Hire a finance manager
fmfire Dismiss the finance manager
fmmand Set the mandate of the finance manager
fmgo Let the finance manager act
fmadd Add money for the finance manager
fmwd Take money from the finance manager
provpick Pick a supplier
ownpick Pick one of your own companies as supplier
provsheet Open the supplier sheet
srcv Set the sourcing variety
srcc Set the sourcing concentration
fixv Fix a supplier
give28 Give money to a city cause
found28 Start a foundation
pk58t Switch a perk on for a company
pk58host Host a rival at a venue
pk58hgo Confirm hosting
pk58lend Lend a luxury item to a manager
pk58lgo Confirm the loan
lx56din Host a dinner on the yacht
"""

MISSING["other"] = """
"""

MISSING["presentation"] = """
acct Choose the account tab
advance Advance a step of the pop-up queue
al30go Alert: go to the thing it names
al30later Alert: remind me later
artview Show a picture
away56 Pick how long to skip away
back Go back one screen
backto Return from a talk to the candidate
btab Bank tab
candback Back from a candidate
candinfo Candidate details
candopen Open a candidate
candpass Pass on a candidate
acandopen Open an assistant candidate
acandback Back from an assistant candidate
mcandopen Open a manager candidate
mcandback Back from a manager candidate
gcandopen Open a group candidate
cel28ok Close a celebration
cel28wall Open the trophy wall from a celebration
ccsheet Open the choose-a-country sheet
citysheet Open the choose-a-city sheet
storysheet Open the choose-a-story sheet
setstory Pick a story at the start
clcset Club view setting
clset Closing sheet option
closepop Open the closing sheet
cofilter Filter the companies list
cosold Show sold companies
confirmgo Confirm a dialog
cotab Company tab
crumb Breadcrumb
crumbroot Breadcrumb root
ddopen Open a dropdown
ddset Set a dropdown
dow56go Open a shortcut from the goals
fin31 Finance view toggle
gaon Connect free web analytics
gaoff Disconnect web analytics
gc28 Giving category tab
go Navigate to a screen
go30 Navigate (round 30)
hdt Holding detail tab
hmode Hiring mode
hmode7 Holding mode
hrole Hiring role
hrole2 Hiring role (second step)
hstep56 Hiring step
itab Invest tab
mailback Back from a mail
mailf Mail filter
mailopen Open a mail
mb56 Manager benefit view
menucont Continue from the menu
menuback Back to the menu
moffer56 Manager offer step
moredocs List optional documents
mstep56 Manager hiring step
mtab Messages tab
none Do nothing
noop Do nothing
nx59do Do the suggested next step
nx59all Show all next steps
nhacc Choose the accountant for a new holding
nhco Choose a company for a new holding
pa56 Personal account view setting
paysel Choose how to pay
payrate Pay rate view
paysrc56 Choose where money comes from
paysrcgo Go to the pay-yourself screen
phapp Open a phone app
phback Back in the phone
phone Open the phone
pickgo Go to a picked place
privacy Show the privacy text
pro56 Ledger Pro switch
pro57 Ledger Pro show-all switch
proask Ledger Pro question
probuy Buy Ledger Pro
prolink Ledger Pro link
promanage Manage Ledger Pro
proplan Ledger Pro plan
proskin Ledger Pro skin
proskinc Ledger Pro skin choice
prorestore Restore Ledger Pro
prostore Ledger Pro store
promoset Promotion sheet setting
repdone Close the week report
repmsgs Show the messages after a report
res36t Results tab
setcat Choose a category
setconf Settings option
setfocus Set the focus of the home screen
setinp Set a text input
sheetclose Close a sheet
slotdel Delete a save slot
slotkeep Keep a save slot
slotload Load a save slot
stt56 Staff table tab
tab Switch tab
thread Open a message thread
threadback Back from a thread
trset Transfer sheet setting
trsheet Open the transfer sheet
tw28 Show a celebration
unl36go Open an unlocked feature
unl36no Close the unlock popup
wel59 Welcome step
wel59end End the welcome
weekrep Open the week report
wr35s Week report section
wr35co Week report: go to the company
wx56c Weather chart setting
msglater Snooze a message
out40ok Close the "meet in the middle" popup
depsheet Open the deposit sheet
books Books view setting
setltv Property loan-to-value view setting
frset Franchise form field
frt56ed Franchise talk editing field
ch12tab Chain page tab
ch12store Chain store page
rn56 Open the rename sheet
cldo Go to the place that fixes a checklist item
codeal Open the deal tab of a company
rb56 Open the rebrand sheet
"""

DESCRIPTIONS = {}
AREA_NAMES = {
 "boards": "Boards, CEO, head office, meetings, academy",
 "startups": "Startups, private equity, listing, crisis",
 "rivals": "Customers, rivals, reviews, key accounts, price wars, market map, software, cyber",
 "advisers": "Advisers, abroad, insurance, suppliers, gifts and similar",
 "other": "Other (fits none of the four areas)",
 "presentation": "Presentation only (navigation, sheets, filters; no gameplay)",
}


# screens and company tabs that exist natively under another name: id -> (native, status key U/P)
SCREEN_MAP = {
 "weekreport": "Reports (ReportsView, ReportPrompt)", "reports": "Reports (ReportsView, ReportPrompt)",
 "awards56": "Phone > Achievements", "trophies28": "Phone > Achievements", "titles": "Phone > Achievements", "top28": "Phone > Rich list",
 "fs58": "Home > First steps", "found36": "Money > Invest > My startups", "startups": "Money > Invest > Startups", "pe56": "Money > Invest > Private equity", "own27": "Company > Money > Owners and shares", "dealroom": "Company > Money > Sell / Owners and shares", "crisis": "Inbox (open decisions; GameEngine.crisisCentre)", "bigmeet": "Money > Invest > Big meeting", "sale": "Company > Sell (CompanySaleSection)", "saletalk": "Company > Sell (CompanySaleSection)",
 "fs58": "Home > First steps", "amb27": "Home > Goals (GoalsCard)", "sale": "Company > Sell (CompanySaleSection)", "saletalk": "Company > Sell (CompanySaleSection)",
 "mgrhire": "Company > Team (manager search)", "managers": "Company > Team", "mgmt56": "Company > Team", "p11talk": "Company > Team > Promote", "pr11": "Company > Team > Promote",
 "store13": "Company > Chain (new store)", "brand56": "Group > Join a franchise", "fr56": "Company > Chain > Franchise talk",
}
TAB_MAP = {
 "invSale": "Company > Money > Owners and shares", "ownersRow": "Company > Money > Owners and shares",
 "franchisor": "Company > Chain > Franchise", "supply": "Company > Chain > Supply", "mgrBanner": "Company > Team", "mgrCard": "Company > Team", "staffProfile": "Company > Team",
 "franchisor": "Company > Chain > Franchise", "supply": "Company > Chain > Supply", "mgrBanner": "Company > Team", "mgrCard": "Company > Team", "staffProfile": "Company > Team", "complaints": "Company > Operations > Complaints",
}
# the rest, by area (one id per word)
MISSING_SCREENS = {
 "boards": "bigmeet bmeet11 bmeet12 board11 board12 boards12 heads hq hqhire hqmk meet meetings office org56 academy staffman tg58",
 "rivals": "rival rivals riv31 rivmoves rvdetail reviews pricewar market map31 world cy56 branch nem28 grp27",
 "advisers": "suppliers give28 anrep11 pk58 net31",
 "other": "month30 paper40 wx56 pacct registry",
 "presentation": "img31 res36 pro59",
}
MISSING_TABS = {
 "advisers": "abroad advisers insurance",
 "rivals": "rivalsCard",
 "other": "demandLevel route",

 "presentation": "DEAL_SUB FIN_SUB OPS_SUB clRows dealKeys dealPart finPart lrow marketRow opsPart",
}

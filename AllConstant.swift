//
//  AllConstant.swift
//  UserAppdemo
//
//  Created by Open on 1/9/23.
//

import Foundation
import CoreData
import Alamofire


/// CoreDataManager   ///////////////

class CoreDataManager {
    static let sharedInstance = CoreDataManager()
    
    private lazy var applicationDocumentDirectory: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[urls.count - 1]
    }()
    
    private lazy var managedObjectModel: NSManagedObjectModel = {
        let modelUrl = Bundle.main.url(forResource: Constants.CoreData.dbName, withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelUrl)!
    }()
    
    private lazy var persistanceCoordinator: NSPersistentStoreCoordinator = {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        let url = self.applicationDocumentDirectory.appendingPathComponent("\(Constants.CoreData.dbName).sqlite")
        var failureResoinse = "Coredata failed"
        do {
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true])
        } catch {
            var dictionary = [String : AnyObject]()
            dictionary[NSLocalizedDescriptionKey] = "Coredata save failed" as AnyObject?
            dictionary[NSLocalizedFailureReasonErrorKey] = "Coredata save failed" as AnyObject?
            dictionary[NSUnderlyingErrorKey] = error as NSError
            
            let wrapperError = NSError(domain: "ERROR_DOMAIN", code: 9999, userInfo: dictionary)
            print("UnResolvedError", wrapperError, wrapperError.userInfo)
            abort()
        }
        
        return coordinator
    }()
    
    lazy var managedObjectContext: NSManagedObjectContext = {
        var managedObjectContext: NSManagedObjectContext?
        
        managedObjectContext = self.persistanceContainer.viewContext
        return managedObjectContext!
    }()
    
    lazy var persistanceContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: Constants.CoreData.dbName)
        container.loadPersistentStores(completionHandler: { storeDescription, error in
            if let error = error as NSError?{
                print("Unresolved error", error, error.userInfo)
                fatalError("Unresolved error \(error) \(error.userInfo)")
            }
        })
        return container
    }()
 
    func getManagedContext() -> NSManagedObjectContext {
        return self.persistanceContainer.viewContext
    }
    
    func saveContext() {
        if managedObjectContext.hasChanges {
            do {
                try managedObjectContext.save()
            } catch {
                let error = error as NSError
                print("Unresolved error", error, error.userInfo)
                abort()
            }
        }
    }
    
    func fetch(entityName: String) -> [NSManagedObject] {
        var managedObjects: [NSManagedObject] = [NSManagedObject]()
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            managedObjects = try getManagedContext().fetch(fetchRequest)
        } catch let error as NSError {
            print("Could not fetch", error, error.userInfo)
        }
        
        return managedObjects
    }
    
    func fetchWithPredicate(entityName: String, predicate: NSPredicate) -> [NSManagedObject] {
        var managedObjects: [NSManagedObject] = [NSManagedObject]()
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = predicate

        do {
            managedObjects = try getManagedContext().fetch(fetchRequest)
        } catch let error as NSError {
            print("Could not fetch", error, error.userInfo)
        }
        
        return managedObjects
    }
    
    func deleteWithPredicate(entityName: String, predicate: NSPredicate) {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = predicate

        do {
            if let fetchRequest = try getManagedContext().fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as? [NSManagedObject] {
                for managedObject in fetchRequest {
                    getManagedContext().delete(managedObject)
                }
                try getManagedContext().save()
            }
        } catch let error as NSError {
            print("Could not fetch", error, error.userInfo)
        }
    }

}



////
          ////   Netwrokmanager

////



public enum NetworkError: Error {
    case genericError(Int?, String?)
    case internetConnectionError
}

extension NetworkError: LocalizedError {
    public var errorTypes: (Int?, String?) {
        switch self {
        case .internetConnectionError:
            return (0, Constants.Message.noInternetMessage)
        case .genericError(let errorCode, let errorString):
            return (errorCode, errorString)
        }
    }
}

class NetworkManager {
    public static func makeRequest<T: Codable>(_ urlRequest: URLRequestConvertible, mode: T.Type, completion: @escaping (Result<T, NetworkError>) -> Void) {
        let request = AF.request(urlRequest).validate().responseString { response in
            switch response.result {
            case .success(let jsonString):
                let jsonData: Data = jsonString.data(using: .utf8)!
                let dict = self.convertStringToDictionary(text: jsonString)
                print("response: ", dict)
                
                let decoder = JSONDecoder()
                do {
                    let decodedJson = try decoder.decode(T.self, from: jsonData)
                    completion(.success(decodedJson))
                } catch {
                    print("response error: ", error.localizedDescription)
                    completion(.failure(.genericError(200, error.localizedDescription)))
                }
            case .failure(let failError):
                print("error response", response)
                do {
                    if let responseData = response.data,
                       let errorResponse = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String : Any] {
                        print("ErrorRespose", errorResponse)
                        completion(.failure(.genericError(response.response?.statusCode, errorResponse["message"] as? String)))
                    }
                } catch {
                    if let descriptionMessage = failError.errorDescription?.contains("The internet connection appears to be offline") {
                        completion(.failure(.genericError(response.response?.statusCode, Constants.Message.noInternetMessage)))
                    }
                    completion(.failure(.genericError(response.response?.statusCode, error.localizedDescription)))
                }
            }
        }
    }
    
    public static func convertStringToDictionary(text: String) -> [String:AnyObject]? {
        if let data = text.data(using: .utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:AnyObject]
                return json
            } catch {
                print("Something went wrong")
            }
        }
        return nil
    }
}

///
///     ////       HTTPRouter
///

enum HTTPRouter: URLRequestConvertible {
        
    case getUserList
    case createUser(user: UserRequestModel)
    
    var path: String {
        switch self {
        case .getUserList,
             .createUser:
            return "user"
        }
    }
    
    var method: String {
        switch self {
        case .getUserList:
            return "GET"
        case .createUser:
            return "POST"
        }
    }
    
    var parameter: [String : Any]? {
        switch self {
        case .createUser(let user):
            return ["full_name": user.fullName ?? "",
                    "email": user.email ?? "",
                    "phone": user.phone ?? "",
                    "address": user.address ?? "",
                    "dob": user.birthdDate ?? "",
                    "gender": user.gender ?? "",
                    "designation": user.designation ?? "",
                    "salary": user.salary ?? 0]
        default:
            return nil
        }
    }
    
    func asURLRequest() throws -> URLRequest {
        let url = URL(string: "\(Constants.Server.baseUrl)" + "\(self.path)")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = self.method
        urlRequest.timeoutInterval = 180
        
        switch self {
        case . getUserList:
            return try URLEncoding.queryString.encode(urlRequest, with: parameter)
        case .createUser:
            return try JSONEncoding.prettyPrinted.encode(urlRequest, with: parameter)
        }
        
    }
}


///
      /// View Model
//

protocol UserListDelegate: AnyObject {
    func getUserList()
    func showAlert(message: String)
}

class UserListViewModel {
    weak private var viewDelegate: UserListDelegate?
    var users: [Users] = [Users]()
    
    init(viewDelegate: UserListDelegate) {
        self.viewDelegate = viewDelegate
        
        if NetworkReachabilityManager()!.isReachable {
            self.getUserList()
        } else {
            self.fetchLocalData()
            self.viewDelegate?.showAlert(message: Constants.Message.noInternetMessage)
        }
    }
    
    func getUserList() {
        if !NetworkReachabilityManager()!.isReachable {
            self.fetchLocalData()
            self.viewDelegate?.showAlert(message: Constants.Message.noInternetMessage)
            return
        }
        
        NetworkManager.makeRequest(HTTPRouter.getUserList, mode: UserDataModel.self) { (result) in
            switch result {
            case .success(let responseData):
                if let usersList = responseData.data, usersList.count > 0 {
                    for object in usersList {
                        object.saveUserObject()
                    }
                    self.fetchLocalData()
                }
            case .failure(let errorMessage):
                self.viewDelegate?.showAlert(message: errorMessage.localizedDescription)
            }
        }
    }
    
    func fetchLocalData(isSearch: Bool = false) {
        if let savedObjects = CoreDataManager.sharedInstance.fetch(entityName: Constants.CoreData.Entity.userList) as? [Users], savedObjects.count > 0 {
            self.users = savedObjects
            if !isSearch {
                self.viewDelegate?.getUserList()
            }
        }
    }
}



/// ////   UserDetailViewModel

protocol UserDetailDelegate: AnyObject {
    func addNewUser()
    func showAlert(message: String)
}

class UserDetailViewModel {
    weak private var viewDelegate: UserDetailDelegate?
    
    init(viewDelegate: UserDetailDelegate) {
        self.viewDelegate = viewDelegate
        
        if !NetworkReachabilityManager()!.isReachable {
            self.viewDelegate?.showAlert(message: Constants.Message.noInternetMessage)
        }
    }
    
    func addNewUser(userRequestModel: UserRequestModel) {
        if !NetworkReachabilityManager()!.isReachable {
            self.viewDelegate?.showAlert(message: Constants.Message.noInternetMessage)
            return
        }
        
        NetworkManager.makeRequest(HTTPRouter.createUser(user: userRequestModel), mode: UserDataModel.self) { (result) in
            switch result {
            case .success(let responseData):
                self.viewDelegate?.addNewUser()
            case .failure(let errorMessage):
                self.viewDelegate?.showAlert(message: errorMessage.localizedDescription)
            }
        }
    }
}



/// Model
struct UserRequestModel {
    var fullName: String?
    var email: String?
    var phone: String?
    var address: String?
    var birthdDate: String?
    var gender: String?
    var designation: String?
    var salary: Int?
}



class UserDataModel: Codable {
    var status: Bool?
    var data: [UserModel]?
    
    
    enum CodingKeys: String, CodingKey {
        case status = "status"
        case data = "data"
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Bool?.self, forKey: .status)
        data = try container.decode([UserModel]?.self, forKey: .data)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(data, forKey: .data)
    }
}

class UserModel: Codable {
    var fullName: String?
    var userId: Int?
    var email: String?
    var profilePicUrl: String?
    var phone: String?
    var address: String?
    var birthDate: String?
    var gender: String?
    var designation: String?
    var salary: Int?
    var createdAt: String?
    var updatedAt: String?
    
    let entityName: String = Constants.CoreData.Entity.userList
    let managedContext = CoreDataManager.sharedInstance.getManagedContext()
    
    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case userId = "id"
        case email = "email"
        case profilePicUrl = "profile_pic_url"
        case phone = "phone"
        case address = "address"
        case birthDate = "dob"
        case gender = "gender"
        case designation = "designation"
        case salary = "salary"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullName = try container.decode(String?.self, forKey: .fullName)
        userId = try container.decode(Int?.self, forKey: .userId)
        email = try container.decode(String?.self, forKey: .email)
        profilePicUrl = try container.decode(String?.self, forKey: .profilePicUrl)
        phone = try container.decode(String?.self, forKey: .phone)
        address = try container.decode(String?.self, forKey: .address)
        birthDate = try container.decode(String?.self, forKey: .birthDate)
        gender = try container.decode(String?.self, forKey: .gender)
        designation = try container.decode(String?.self, forKey: .designation)
        salary = try container.decode(Int?.self, forKey: .salary)
        createdAt = try container.decode(String?.self, forKey: .createdAt)
        updatedAt = try container.decode(String?.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(userId, forKey: .userId)
        try container.encode(email, forKey: .email)
        try container.encode(profilePicUrl, forKey: .profilePicUrl)
        try container.encode(phone, forKey: .phone)
        try container.encode(address, forKey: .address)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encode(gender, forKey: .gender)
        try container.encode(designation, forKey: .designation)
        try container.encode(salary, forKey: .salary)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func saveUserObject() {
        if let savedUserObject = CoreDataManager.sharedInstance.fetchWithPredicate(entityName: self.entityName, predicate: NSPredicate(format: "userId = \(self.userId ?? 0)")) as? [Users], savedUserObject.count > 0 {
            self.update(user: savedUserObject[0])
        } else {
            self.insertNewUserObject()
        }
    }
    
    func insertNewUserObject() {
        let entity = NSEntityDescription.entity(forEntityName: entityName, in: managedContext)!
        let object: Users = NSManagedObject(entity: entity, insertInto: managedContext) as! Users
        
        self.update(user: object)
    }
    
    func update(user: Users) {
        user.userId = Int64(self.userId ?? 0)
        user.fullName = self.fullName ?? ""
        user.email = self.email ?? ""
        user.profilePicUrl = self.profilePicUrl ?? ""
        user.phone = self.phone ?? ""
        user.address = self.address ?? ""
        user.birthDate = self.birthDate ?? ""
        user.designation = self.designation ?? ""
        user.gender = self.gender ?? ""
        user.salary = Int64(self.salary ?? 0)
        user.createdAt = self.createdAt ?? ""
        user.updatedAt = self.updatedAt ?? ""
        
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("Could not save", error, error.userInfo)
        }
    }
    
}



/// Constant
///
///


struct Constants {
    struct Server {
        static let baseUrl = "public/api/"
    }
    
    struct Message {
        static let noInternetMessage = "No interenet connection."
        static let ok = "Ok"
        static let cancel = "Cancel"
    }
    
    struct CoreData {
        static let dbName = "UserAppdemo"

        struct Entity {
            static let userList = "Users"
        }
    }
}


///
/// UserListViewController
///

class UserListViewController: UIViewController {
     
    @IBOutlet weak var userTableView: UITableView!
    @IBOutlet weak var searchBar: UISearchBar!

    lazy var viewModel = UserListViewModel(viewDelegate: self)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.viewModel.fetchLocalData()
    }
    
    func setupView() {
        userTableView.register(UINib(nibName: "UserListTableViewCell", bundle: nil), forCellReuseIdentifier: "UserListTableViewCell")
        userTableView.delegate = self
        userTableView.dataSource = self
        searchBar.delegate = self
    }
    
    @IBAction func addUserClicked(_ sender: UIBarButtonItem) {
        if let userDetailViewController = self.storyboard?.instantiateViewController(withIdentifier: "UserDetailViewController") as? UserDetailViewController {
            userDetailViewController.user = nil
            self.navigationController?.pushViewController(userDetailViewController, animated: true)
        }
    }
}

extension UserListViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if !searchText.isEmpty {
            self.viewModel.fetchLocalData(isSearch: true)
            self.viewModel.users = self.viewModel.users.filter { $0.fullName?.contains(searchText.lowercased()) as? Bool ?? false}
            self.userTableView.reloadData()
        } else {
            self.viewModel.fetchLocalData()
        }
    }
}

extension UserListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.viewModel.users.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserListTableViewCell") as? UserListTableViewCell
        cell?.setupCell(user: viewModel.users[indexPath.row])
        return cell ?? UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let userDetailViewController = self.storyboard?.instantiateViewController(withIdentifier: "UserDetailViewController") as? UserDetailViewController {
            userDetailViewController.user = self.viewModel.users[indexPath.row]
            self.navigationController?.pushViewController(userDetailViewController, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if (editingStyle == .delete) {
            CoreDataManager.sharedInstance.deleteWithPredicate(entityName: Constants.CoreData.Entity.userList, predicate: NSPredicate(format: "userId = \(self.viewModel.users[indexPath.row].userId)"))
            self.viewModel.fetchLocalData()
        }
    }
}

extension UserListViewController: UserListDelegate {
    func getUserList() {
        self.userTableView.reloadData()
    }
    
    func showAlert(message: String) {
        let alertController = UIAlertController(title: "Alert", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: { action in
            self.userTableView.reloadData()
        }))
        self.present(alertController, animated: true, completion: nil)
    }

}

///   User Detail ViewController
///

class UserDetailViewController: UIViewController {
    
    @IBOutlet weak var userDetailTableView: UITableView!
    @IBOutlet weak var saveButton: UIButton!

    var user: Users?
    lazy var viewModel = UserDetailViewModel(viewDelegate: self)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupView()
    }
    
    func setupView() {
        self.title = "Detail"
        userDetailTableView.register(UINib(nibName: "UserProfilePicTableViewCell", bundle: nil), forCellReuseIdentifier: "UserProfilePicTableViewCell")
        userDetailTableView.register(UINib(nibName: "UserDetailTableViewCell", bundle: nil), forCellReuseIdentifier: "UserDetailTableViewCell")

        self.userDetailTableView.delegate = self
        self.userDetailTableView.dataSource = self
        if let _ = user {
            self.saveButton.setTitle("Save", for: .normal)
        } else {
            self.saveButton.setTitle("Add", for: .normal)
        }
        
        self.saveButton.setCornerRadius()
    }

    @IBAction func saveClicked(_ sender: UIButton) {
        if user == nil {
            let userRequestModel = UserRequestModel(fullName: self.user?.fullName ?? "",
                                                    email: self.user?.email ?? "",
                                                    phone: self.user?.phone ?? "",
                                                    address: self.user?.address ?? "",
                                                    birthdDate: self.user?.birthDate ?? "",
                                                    gender: self.user?.gender ?? "",
                                                    designation: self.user?.designation ?? "",
                                                    salary: Int(self.user?.salary ?? 0))
            self.viewModel.addNewUser(userRequestModel: userRequestModel)
        } else {
            let userRequestModel = UserRequestModel(fullName: self.user?.fullName ?? "",
                                                    email: self.user?.email ?? "",
                                                    phone: self.user?.phone ?? "",
                                                    address: self.user?.address ?? "",
                                                    birthdDate: self.user?.birthDate ?? "",
                                                    gender: self.user?.gender ?? "",
                                                    designation: self.user?.designation ?? "",
                                                    salary: Int(self.user?.salary ?? 0))
            self.viewModel.addNewUser(userRequestModel: userRequestModel)
            self.navigationController?.popViewController(animated: true)
        }
    }
}

extension UserDetailViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 1 : 8
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let userProfilePicCell = tableView.dequeueReusableCell(withIdentifier: "UserProfilePicTableViewCell") as? UserProfilePicTableViewCell
            if let user = self.user {
                userProfilePicCell?.setupCell(user: user)
            }
            return userProfilePicCell ?? UITableViewCell()
        }
        
        let userDetailCell = tableView.dequeueReusableCell(withIdentifier: "UserDetailTableViewCell") as? UserDetailTableViewCell
        userDetailCell?.detailTextField.tag = indexPath.row
        userDetailCell?.detailTextField.delegate = self
        
        if let user = self.user {
            switch indexPath.row {
            case 0:
                userDetailCell?.setupCell(detailPlaceholder: "Full Name", detailText: user.fullName ?? "")
            case 1:
                userDetailCell?.setupCell(detailPlaceholder: "Email", detailText: user.email ?? "")
            case 2:
                userDetailCell?.setupCell(detailPlaceholder: "Phone Number", detailText: user.phone ?? "")
            case 3:
                userDetailCell?.setupCell(detailPlaceholder: "Address", detailText: user.address ?? "")
            case 4:
                userDetailCell?.setupCell(detailPlaceholder: "BirthDate", detailText: user.birthDate ?? "")
            case 5:
                userDetailCell?.setupCell(detailPlaceholder: "Gender", detailText: user.gender ?? "")
            case 6:
                userDetailCell?.setupCell(detailPlaceholder: "Designation", detailText: user.designation ?? "")
            case 7:
                userDetailCell?.setupCell(detailPlaceholder: "Salary", detailText: "\(user.salary)")
            default:
                break
            }
        } else {
            switch indexPath.row {
            case 0:
                userDetailCell?.setupCell(detailPlaceholder: "Full Name", detailText: "")
            case 1:
                userDetailCell?.setupCell(detailPlaceholder: "Email", detailText: "")
            case 2:
                userDetailCell?.setupCell(detailPlaceholder: "Phone Number", detailText: "")
            case 3:
                userDetailCell?.setupCell(detailPlaceholder: "Address", detailText:  "")
            case 4:
                userDetailCell?.setupCell(detailPlaceholder: "BirthDate", detailText: "")
            case 5:
                userDetailCell?.setupCell(detailPlaceholder: "Gender", detailText: "")
            case 6:
                userDetailCell?.setupCell(detailPlaceholder: "Designation", detailText: "")
            case 7:
                userDetailCell?.setupCell(detailPlaceholder: "Salary", detailText: "")
            default:
                break
            }
        }
        return userDetailCell ?? UITableViewCell()
    }
}

extension UserDetailViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        if self.user == nil {
            let managedContext = CoreDataManager.sharedInstance.getManagedContext()

            let entity = NSEntityDescription.entity(forEntityName: Constants.CoreData.Entity.userList, in: managedContext)!
            self.user = (NSManagedObject(entity: entity, insertInto: managedContext) as! Users)
        }
        switch textField.tag {
        case 0:
            self.user?.fullName = textField.text ?? ""
        case 1:
            self.user?.email = textField.text ?? ""
        case 2:
            self.user?.phone = textField.text ?? ""
        case 3:
            self.user?.address = textField.text ?? ""
        case 4:
            self.user?.birthDate = textField.text ?? ""
        case 5:
            self.user?.gender = textField.text ?? ""
        case 6:
            self.user?.designation = textField.text ?? ""
        case 7:
            self.user?.salary = Int64(textField.text ?? "0") ?? 0
        default:
            break
        }
    }
}

extension UserDetailViewController: UserDetailDelegate {
    func addNewUser() {
        let alertController = UIAlertController(title: "Alert", message: "New user added successfully", preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: { action in
            self.navigationController?.popViewController(animated: true)
        }))
        self.present(alertController, animated: true, completion: nil)
    }
    
    func showAlert(message: String) {
        let alertController = UIAlertController(title: "Alert", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
        self.present(alertController, animated: true, completion: nil)
    }
}

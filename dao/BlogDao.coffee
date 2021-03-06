BlogModel = require("./../models/BlogModel").Blog
fs = require("fs")
msg = require("./../libs/msg")
tmpl = require("./../libs/tmpl")
marked = require("marked")
config = require("./../config")
tools = require("./../libs/tools")
nodemailer = require("nodemailer")
moment = require "moment"

BlogDao =
	model: BlogModel

	# 保存博客，新建和编辑
	saveBlog: (user, blog, callback) ->
		blog.author_id = user._id
		smtpTransport = nodemailer.createTransport "SMTP",
		    service: "Gmail",
		    auth: config.admin_email

		# 此处写Markdown文件，放在以用户id为名的文件夹中
		# For Windows
		myFolderUrl = config.site.MARKDOWN_DICT + '\\' + blog.author_id;
		myFileUrl = myFolderUrl + "\\" + blog.title + ".md"

		# For Mac
		# myFolderUrl = config.site.MARKDOWN_DICT + '\/' + blog.author_id;
		# myFileUrl = myFolderUrl + "\/" + blog.title + ".md"
		# 创建存放所有博客的根目录，部署后可去除
		tools.mkdirArticleSync()

		# 如果该用户是第一次写博客，为他创建文件夹
		if not fs.existsSync(myFolderUrl)
			fs.mkdirSync myFolderUrl

		# 将博客内容写入文件
		fs.writeFile myFileUrl, blog.articleContent, (err) ->
			return callback msg.ARTICLE.writeFileError,null if err
			blog.url = myFileUrl
			# Tags 以数组存储
			blog.tags = blog.tags.toString().split ','
			newArticle = new BlogModel(blog)

			# 更新
			if blog._id
				query = _id: newArticle._id
				updateArticle = 
					title: newArticle.title
					tags: newArticle.tags
					update_at: new Date()
				BlogModel.update query, updateArticle, (err, numAffected) ->
					return callback msg.MAIN.error,null if err
					callback null, numAffected
			# 新建
			else
				newArticle.save (err, curArticle) ->
					return callback err,null if err

					mailOptions = 
					    from: "UEBlog"
					    to: config.receivers.join('@iflytek.com,') + '@iflytek.com'
					    subject: "新博客通知：#{curArticle.title}"
					    html: tmpl.mail(curArticle, user)

					smtpTransport.sendMail mailOptions, (error, response) ->
					    if error
					        console.log(error)
					    else
					        console.log("Message sent: " + response.message)

					smtpTransport.close();
					callback null, curArticle

	# 分页获取所有博客列表
	# 参数：页码，回调函数
	getAll: (page, callback) ->
		start = tools.calcStart(page)
		# 查询语句步骤分别是：查询所有博客，跳过前页的条目，限制一页数，查询博客作者
		@model.find().skip(start).limit(config.site.PAGE_COUNT).sort('-update_at').populate('author_id').populate('stared').exec (err, arts) ->
			return callback err, null if err
			i = 0
			# 此处将Bson转换成Json一是避免中文乱码，二是对Json对象的操作可以顺利传到客户端
			# 然后读取文件中的文章内容
			artsObj = JSON.parse(JSON.stringify(arts))
			for art in artsObj
				artsObj[i].articleContent = marked(fs.readFileSync art.url,{encoding:'utf-8'})
				callback null, artsObj if ++i == arts.length
	
	# 获取一条博客记录
	getOneById: (id, decode, callback) ->
		BlogModel.findById(id).populate('author_id').populate('stared').exec (err, article) ->
			callback err, null if err
			artObj = JSON.parse(JSON.stringify(article))
			fs.readFile artObj.url,{encoding:'utf-8'}, (err, data) ->
				artObj.articleContent = if decode then data else marked(data)
				callback null, artObj

	# 删除一条博客记录
	deleteOneById: (id, callback) ->
		BlogModel.findById id, (err, blog) ->
			return callback msg.ARTICLE.notExist if err
			blog.remove (err)->
				return callback msg.MAIN.error if err
				fs.unlink blog.url, (err) ->
					callback true
	
	# 记录博客访问
	visit: (blogId, option, callback) ->
		BlogModel.findByIdAndUpdate blogId, option, (err, number) ->
			return callback err, null if err
			callback null, number
			

module.exports = BlogDao;